defmodule RunlocalWeb.TunnelChannel do
  use Phoenix.Channel
  require Logger

  @two_hours_ms 2 * 60 * 60 * 1000
  @max_tunnels_per_ip 5
  @max_response_size 10_000_000

  @impl true
  def join("tunnel:connect", _payload, socket) do
    client_ip = socket.assigns[:client_ip]

    if client_ip && Runlocal.Registry.count_by_ip(client_ip) >= @max_tunnels_per_ip do
      {:error, %{reason: "too_many_tunnels"}}
    else
      case resolve_subdomain(socket) do
        {:ok, subdomain, fallback} ->
          authenticated = socket.assigns[:api_key] != nil and fallback == nil
          Runlocal.Registry.register(subdomain, self(), client_ip)
          Runlocal.Stats.track_tunnel(client_ip)

          unless authenticated do
            Process.send_after(self(), :ttl_expired, @two_hours_ms)
          end

          url = build_url(subdomain)

          socket =
            socket
            |> assign(:subdomain, subdomain)
            |> assign(:pending_requests, %{})

          send(self(), {:after_join, url, fallback})
          {:ok, socket}

        {:error, reason} ->
          {:error, %{reason: reason}}
      end
    end
  end

  defp resolve_subdomain(socket) do
    api_key = socket.assigns[:api_key]

    if api_key do
      case verify_subdomain(api_key) do
        {:ok, subdomain} ->
          if Runlocal.Registry.lookup(subdomain) do
            # Stable subdomain is in use, fall back to random
            {:ok, Runlocal.Subdomain.generate(), subdomain}
          else
            {:ok, subdomain, nil}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, Runlocal.Subdomain.generate(), nil}
    end
  end

  defp verify_subdomain(api_key) do
    runlater_url = Application.get_env(:runlocal, :runlater_api_url, "https://runlater.eu")
    url = "#{runlater_url}/api/v1/verify-subdomain"
    body = "{}"

    headers = [
      {~c"authorization", ~c"Bearer #{api_key}"},
      {~c"content-type", ~c"application/json"}
    ]

    case :httpc.request(:post, {String.to_charlist(url), headers, ~c"application/json", body}, [{:timeout, 5000}], []) do
      {:ok, {{_, 200, _}, _, resp_body}} ->
        case Jason.decode(to_string(resp_body)) do
          {:ok, %{"valid" => true, "subdomain" => subdomain}} ->
            {:ok, subdomain}

          _ ->
            {:error, "invalid response from runlater"}
        end

      {:ok, {{_, 401, _}, _, _}} ->
        {:error, "invalid_api_key"}

      {:ok, {{_, status, _}, _, resp_body}} ->
        Logger.warning("[Channel] Subdomain verification failed: status=#{status} body=#{resp_body}")
        {:error, "verification_failed"}

      {:error, reason} ->
        Logger.warning("[Channel] Subdomain verification error: #{inspect(reason)}")
        {:error, "verification_unavailable"}
    end
  end

  defp build_url(subdomain) do
    base_domain = Application.get_env(:runlocal, :base_domain, "localhost")

    if base_domain == "localhost" do
      "http://#{subdomain}.localhost:4000"
    else
      "https://#{subdomain}.#{base_domain}"
    end
  end

  @impl true
  def handle_info({:after_join, url, fallback}, socket) do
    msg = %{"url" => url, "subdomain" => socket.assigns.subdomain}

    msg =
      if fallback do
        Map.merge(msg, %{"fallback" => true, "requested_subdomain" => fallback})
      else
        msg
      end

    push(socket, "tunnel_created", msg)
    {:noreply, socket}
  end

  def handle_info({:http_request, request_id, request_data, caller_pid}, socket) do
    Logger.info("[Channel] Received http_request #{request_id}, pushing to client")
    pending = Map.put(socket.assigns.pending_requests, request_id, caller_pid)
    socket = assign(socket, :pending_requests, pending)

    push(socket, "http_request", Map.put(request_data, "request_id", request_id))
    {:noreply, socket}
  end

  def handle_info(:ttl_expired, socket) do
    {:stop, :normal, socket}
  end

  @impl true
  def handle_in("http_response", payload, socket) do
    request_id = payload["request_id"]
    Logger.info("[Channel] Received http_response for #{request_id}, pending keys: #{inspect(Map.keys(socket.assigns.pending_requests))}")

    response_body = payload["body"] || ""

    if byte_size(response_body) > @max_response_size do
      case Map.pop(socket.assigns.pending_requests, request_id) do
        {nil, _} ->
          {:noreply, socket}

        {caller_pid, remaining} ->
          send(caller_pid, {:tunnel_response, request_id, %{"status" => 502, "body" => "Response too large"}})
          {:noreply, assign(socket, :pending_requests, remaining)}
      end
    else
      case Map.pop(socket.assigns.pending_requests, request_id) do
        {nil, _} ->
          Logger.warning("[Channel] No pending request found for #{request_id}")
          {:noreply, socket}

        {caller_pid, remaining} ->
          Logger.info("[Channel] Sending response to caller #{inspect(caller_pid)} alive=#{Process.alive?(caller_pid)}")
          send(caller_pid, {:tunnel_response, request_id, payload})
          {:noreply, assign(socket, :pending_requests, remaining)}
      end
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if subdomain = socket.assigns[:subdomain] do
      Runlocal.Registry.unregister(subdomain)
      Runlocal.RateLimiter.cleanup(subdomain)
      Runlocal.BandwidthLimiter.cleanup(subdomain)
    end

    :ok
  end
end
