defmodule RunlocalWeb.TunnelChannel do
  use Phoenix.Channel
  require Logger

  @two_hours_ms 2 * 60 * 60 * 1000
  @max_tunnels_per_ip 5
  @max_anonymous_tunnels_per_ip 1
  @max_response_size 10_000_000
  @preview_bytes 10_240
  @server_caps ["stream"]

  @impl true
  def join("tunnel:connect", _payload, socket) do
    client_ip = socket.assigns[:client_ip]

    # Anonymous clients are limited to a single concurrent tunnel per IP;
    # clients presenting an api_key get the higher per-IP allowance. In
    # :runlater mode an invalid api_key is rejected later in resolve_subdomain,
    # so a bogus key cannot be used to exceed the anonymous limit.
    max_tunnels =
      if socket.assigns[:api_key],
        do: @max_tunnels_per_ip,
        else: @max_anonymous_tunnels_per_ip

    cond do
      network_blocked?(socket, client_ip) ->
        Logger.warning(
          "[Tunnel] rejected reason=blocked_network ip=#{client_ip} asn=#{Runlocal.GeoIP.asn(client_ip)}"
        )

        {:error, %{reason: "blocked_network"}}

      client_ip && Runlocal.Registry.count_by_ip(client_ip) >= max_tunnels ->
        Logger.warning(
          "[Tunnel] rejected reason=too_many_tunnels ip=#{client_ip} max=#{max_tunnels}"
        )

        {:error, %{reason: "too_many_tunnels"}}

      true ->
        case resolve_subdomain(socket) do
          {:ok, subdomain, fallback} ->
            authenticated = socket.assigns[:api_key] != nil and fallback == nil
            # The proxy reads these to decide whether a large request body may
            # be streamed to this client or has to be buffered.
            Runlocal.Registry.set_caps(subdomain, self(), socket.assigns[:caps])
            Runlocal.Stats.track_tunnel(client_ip)

            Logger.info(
              "[Tunnel] created subdomain=#{subdomain} ip=#{client_ip} authenticated=#{authenticated}"
            )

            unless authenticated do
              Process.send_after(self(), :ttl_expired, @two_hours_ms)
            end

            url = build_url(subdomain)
            inspect_token = sign_inspect_token(subdomain)

            socket =
              socket
              |> assign(:subdomain, subdomain)
              |> assign(:pending_requests, %{})
              |> assign(:ws_connections, %{})

            send(self(), {:after_join, url, fallback, inspect_token})
            {:ok, socket}

          {:error, reason} ->
            {:error, %{reason: reason}}
        end
    end
  end

  # Tunnel creation from blocklisted networks (ASNs) is refused for anonymous
  # clients. Only :runlater mode actually verifies api_keys (in
  # resolve_subdomain), so only there does presenting a key earn a bypass —
  # an invalid key is still rejected before a tunnel is created. In
  # :random/:custom mode keys are never verified and grant no bypass.
  defp network_blocked?(socket, client_ip) do
    verified_key? =
      socket.assigns[:api_key] != nil and
        Application.get_env(:runlocal, :subdomain_mode, :random) == :runlater

    not verified_key? and Runlocal.GeoIP.blocked_asn?(client_ip)
  end

  # Resolvers return `{:ok, subdomain, fallback}` with `subdomain` already
  # claimed in the registry, so that the name cannot be taken between deciding
  # on it and registering it.
  defp resolve_subdomain(socket) do
    mode = Application.get_env(:runlocal, :subdomain_mode, :random)
    api_key = socket.assigns[:api_key]
    requested_subdomain = socket.assigns[:requested_subdomain]
    client_ip = socket.assigns[:client_ip]

    case mode do
      :random ->
        {:ok, claim_random(client_ip), nil}

      :custom ->
        resolve_custom_subdomain(requested_subdomain, client_ip)

      :runlater ->
        resolve_runlater_subdomain(api_key, requested_subdomain, client_ip)
    end
  end

  defp resolve_custom_subdomain(requested, client_ip)
       when is_binary(requested) and requested != "" do
    if Runlocal.Subdomain.valid_subdomain?(requested) do
      case claim_or_fallback(requested, client_ip) do
        {:ok, _subdomain, nil} = ok -> ok
        {:ok, _subdomain, _fallback} -> {:error, "subdomain_taken"}
      end
    else
      {:ok, claim_random(client_ip), nil}
    end
  end

  defp resolve_custom_subdomain(_, client_ip), do: {:ok, claim_random(client_ip), nil}

  defp resolve_runlater_subdomain(api_key, requested_subdomain, client_ip) do
    if api_key do
      case verify_tunnel(api_key) do
        {:ok, org_slug, tier} ->
          org_slug
          |> Runlocal.Subdomain.pick_subdomain(tier, requested_subdomain)
          |> claim_or_fallback(client_ip)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, claim_random(client_ip), nil}
    end
  end

  # Claims `desired`, dropping to a random subdomain only when it is genuinely
  # held by another live tunnel. A reconnecting client — same IP, new socket —
  # takes the name back rather than being exiled to a random one, which matters
  # because an org slug can only ever front a single tunnel: leaving the zombie
  # in place would 404 the real hostname. The displaced channel is stopped so it
  # does not linger.
  defp claim_or_fallback(desired, client_ip) do
    case Runlocal.Registry.claim(desired, self(), client_ip) do
      {:ok, :claimed} ->
        {:ok, desired, nil}

      {:ok, {:evicted_stale, owner}} ->
        Logger.info("[Tunnel] reclaimed subdomain=#{desired} from dead channel #{inspect(owner)}")

        {:ok, desired, nil}

      {:ok, {:took_over, owner}} ->
        Logger.info("[Tunnel] reconnect took over subdomain=#{desired} ip=#{client_ip}")
        send(owner, :replaced)
        {:ok, desired, nil}

      {:taken, owner} ->
        Logger.info(
          "[Tunnel] subdomain=#{desired} held by #{inspect(owner)}, falling back to random"
        )

        {:ok, claim_random(client_ip), desired}
    end
  end

  defp claim_random(client_ip) do
    subdomain = Runlocal.Subdomain.generate()

    case Runlocal.Registry.claim(subdomain, self(), client_ip) do
      {:ok, _} -> subdomain
      {:taken, _} -> claim_random(client_ip)
    end
  end

  defp verify_tunnel(api_key) do
    runlater_url = Application.get_env(:runlocal, :runlater_api_url, "https://runlater.eu")
    url = "#{runlater_url}/api/v1/verify-tunnel"
    body = "{}"

    headers = [
      {~c"authorization", ~c"Bearer #{api_key}"},
      {~c"content-type", ~c"application/json"}
    ]

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, ~c"application/json", body},
           [{:timeout, 5000}],
           []
         ) do
      {:ok, {{_, 200, _}, _, resp_body}} ->
        case Jason.decode(to_string(resp_body)) do
          {:ok, %{"valid" => true, "org_slug" => org_slug, "tier" => tier}} ->
            {:ok, org_slug, tier}

          _ ->
            {:error, "invalid response from runlater"}
        end

      {:ok, {{_, 401, _}, _, _}} ->
        {:error, "invalid_api_key"}

      {:ok, {{_, status, _}, _, resp_body}} ->
        Logger.warning("[Channel] Tunnel verification failed: status=#{status} body=#{resp_body}")
        {:error, "verification_failed"}

      {:error, reason} ->
        Logger.warning("[Channel] Tunnel verification error: #{inspect(reason)}")
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
  def handle_info({:after_join, url, fallback, inspect_token}, socket) do
    msg = %{
      "url" => url,
      "subdomain" => socket.assigns.subdomain,
      "inspect_token" => inspect_token,
      # What this server understands. A client must not send frames the server
      # has no clause for: an unmatched handle_in/3 crashes the channel and
      # takes the tunnel down with it.
      "caps" => @server_caps
    }

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
    socket = track_pending(socket, request_id, caller_pid)

    broadcast_new_request(socket.assigns.subdomain, request_id, request_data)

    payload =
      request_data
      |> Map.put("request_id", request_id)
      |> encode_outbound_body(socket)

    push(socket, "http_request", payload)
    {:noreply, socket}
  end

  # A request whose body is too large to buffer: the head goes out first and the
  # body follows as chunks, so neither side ever holds the whole upload.
  def handle_info({:http_request_start, request_id, request_data, caller_pid}, socket) do
    socket = track_pending(socket, request_id, caller_pid)

    broadcast_new_request(socket.assigns.subdomain, request_id, request_data)

    payload =
      request_data
      |> Map.put("request_id", request_id)
      |> Map.put("body_streaming", true)
      |> encode_outbound_body(socket)

    push(socket, "http_request_start", payload)
    {:noreply, socket}
  end

  def handle_info({:http_request_chunk, request_id, data}, socket) do
    push(socket, "http_request_chunk", %{
      "request_id" => request_id,
      "body" => Base.encode64(data),
      "body_encoding" => "base64"
    })

    {:noreply, socket}
  end

  def handle_info({:http_request_end, request_id}, socket) do
    push(socket, "http_request_end", %{"request_id" => request_id})
    {:noreply, socket}
  end

  # The visitor went away, or the response outgrew its budget. Tell the client
  # to abandon the upstream request instead of producing bytes nobody will read.
  def handle_info({:cancel_request, request_id}, socket) do
    push(socket, "http_cancel", %{"request_id" => request_id})
    {:noreply, drop_pending(socket, request_id)}
  end

  def handle_info({:ws_upgrade, ws_id, ws_proxy_pid, request_data}, socket) do
    Process.monitor(ws_proxy_pid)
    ws_connections = Map.put(socket.assigns.ws_connections, ws_id, ws_proxy_pid)
    socket = assign(socket, :ws_connections, ws_connections)

    push(socket, "ws_upgrade", %{
      "ws_id" => ws_id,
      "path" => request_data["path"],
      "query_string" => request_data["query_string"],
      "headers" => request_data["headers"]
    })

    {:noreply, socket}
  end

  def handle_info({:ws_client_frame, ws_id, data, opcode}, socket) do
    payload = %{"ws_id" => ws_id, "opcode" => to_string(opcode)}

    payload =
      case opcode do
        :binary -> Map.put(payload, "data", Base.encode64(data))
        _ -> Map.put(payload, "data", data)
      end

    push(socket, "ws_client_frame", payload)
    {:noreply, socket}
  end

  def handle_info({:ws_closed, ws_id}, socket) do
    ws_connections = Map.delete(socket.assigns.ws_connections, ws_id)
    socket = assign(socket, :ws_connections, ws_connections)
    push(socket, "ws_close", %{"ws_id" => ws_id})
    {:noreply, socket}
  end

  def handle_info({:DOWN, _, :process, pid, _}, socket) do
    # A WsProxy process died — remove it from ws_connections
    ws_connections =
      socket.assigns.ws_connections
      |> Enum.reject(fn {_id, proxy_pid} -> proxy_pid == pid end)
      |> Map.new()

    socket = assign(socket, :ws_connections, ws_connections)
    {:noreply, socket}
  end

  def handle_info(:ttl_expired, socket) do
    {:stop, :normal, socket}
  end

  # A newer connection claimed this channel's subdomain. The registration now
  # points at the replacement, so `terminate/2`'s guarded unregister leaves it
  # alone.
  def handle_info(:replaced, socket) do
    {:stop, {:shutdown, :replaced}, socket}
  end

  @impl true
  def handle_in("http_response", payload, socket) do
    request_id = payload["request_id"]

    Logger.info(
      "[Channel] Received http_response for #{request_id}, pending keys: #{inspect(Map.keys(socket.assigns.pending_requests))}"
    )

    payload = decode_inbound_body(payload)
    response_body = payload["body"] || ""

    case Map.pop(socket.assigns.pending_requests, request_id) do
      {nil, _} ->
        Logger.warning("[Channel] No pending request found for #{request_id}")
        {:noreply, socket}

      {pending, remaining} ->
        # This is the whole-response-in-one-frame path, so the cap still
        # applies. Clients that stream (`http_response_start`) are not bounded
        # by it — that is the point of streaming.
        payload =
          if byte_size(response_body) > @max_response_size do
            %{"status" => 502, "body" => "Response too large"}
          else
            payload
          end

        broadcast_request_updated(
          socket.assigns.subdomain,
          request_id,
          payload,
          pending.started_at
        )

        send(pending.caller, {:tunnel_response, request_id, payload})
        {:noreply, assign(socket, :pending_requests, remaining)}
    end
  end

  def handle_in("http_response_start", payload, socket) do
    request_id = payload["request_id"]

    case Map.fetch(socket.assigns.pending_requests, request_id) do
      :error ->
        Logger.warning("[Channel] No pending request found for #{request_id}")
        {:noreply, socket}

      {:ok, pending} ->
        status = payload["status"] || 502
        headers = payload["headers"] || []
        send(pending.caller, {:tunnel_response_start, request_id, status, headers})

        pending = %{pending | status: status, headers: headers}
        {:noreply, put_pending(socket, request_id, pending)}
    end
  end

  def handle_in("http_response_chunk", payload, socket) do
    request_id = payload["request_id"]

    case Map.fetch(socket.assigns.pending_requests, request_id) do
      :error ->
        {:noreply, socket}

      {:ok, pending} ->
        data = decode_inbound_body(payload)["body"] || ""
        send(pending.caller, {:tunnel_response_chunk, request_id, data})
        {:noreply, put_pending(socket, request_id, accumulate_preview(pending, data))}
    end
  end

  def handle_in("http_response_end", payload, socket) do
    request_id = payload["request_id"]

    case Map.pop(socket.assigns.pending_requests, request_id) do
      {nil, _} ->
        {:noreply, socket}

      {pending, remaining} ->
        send(pending.caller, {:tunnel_response_end, request_id})

        broadcast_request_updated(
          socket.assigns.subdomain,
          request_id,
          %{
            "status" => pending.status,
            "headers" => pending.headers,
            "body" => pending.preview,
            "body_size" => pending.size
          },
          pending.started_at
        )

        {:noreply, assign(socket, :pending_requests, remaining)}
    end
  end

  def handle_in("ws_frame", %{"ws_id" => ws_id, "data" => data} = payload, socket) do
    case Map.get(socket.assigns.ws_connections, ws_id) do
      nil ->
        {:noreply, socket}

      ws_proxy_pid ->
        opcode = String.to_existing_atom(payload["opcode"] || "text")

        frame_data =
          case opcode do
            :binary -> Base.decode64!(data)
            _ -> data
          end

        send(ws_proxy_pid, {:ws_frame, frame_data, opcode})
        {:noreply, socket}
    end
  end

  def handle_in("ws_close", %{"ws_id" => ws_id}, socket) do
    case Map.get(socket.assigns.ws_connections, ws_id) do
      nil ->
        {:noreply, socket}

      ws_proxy_pid ->
        send(ws_proxy_pid, {:ws_close})
        {:noreply, socket}
    end
  end

  defp track_pending(socket, request_id, caller_pid) do
    pending = %{
      caller: caller_pid,
      started_at: System.monotonic_time(:millisecond),
      status: nil,
      headers: nil,
      preview: "",
      size: 0
    }

    put_pending(socket, request_id, pending)
  end

  defp put_pending(socket, request_id, pending) do
    assign(
      socket,
      :pending_requests,
      Map.put(socket.assigns.pending_requests, request_id, pending)
    )
  end

  defp drop_pending(socket, request_id) do
    assign(socket, :pending_requests, Map.delete(socket.assigns.pending_requests, request_id))
  end

  # The inspector only ever shows the head of a body, so a streamed response
  # keeps the first @preview_bytes and counts the rest rather than retaining it.
  defp accumulate_preview(pending, data) do
    missing = @preview_bytes - byte_size(pending.preview)

    preview =
      if missing > 0 do
        pending.preview <> binary_part(data, 0, min(missing, byte_size(data)))
      else
        pending.preview
      end

    %{pending | preview: preview, size: pending.size + byte_size(data)}
  end

  defp encode_outbound_body(payload, socket) do
    if client_supports?(socket, "binary-bodies") do
      body = payload["body"] || ""

      payload
      |> Map.put("body", Base.encode64(body))
      |> Map.put("body_encoding", "base64")
    else
      payload
    end
  end

  defp client_supports?(socket, cap) do
    case socket.assigns[:caps] do
      %MapSet{} = caps -> MapSet.member?(caps, cap)
      _ -> false
    end
  end

  defp decode_inbound_body(payload) do
    case payload["body_encoding"] do
      "base64" ->
        body = payload["body"] || ""
        Map.put(payload, "body", Base.decode64!(body))

      _ ->
        payload
    end
  end

  defp broadcast_new_request(subdomain, request_id, request_data) do
    entry = %{
      id: request_id,
      method: request_data["method"],
      path: request_data["path"],
      query_string: request_data["query_string"],
      request_headers: request_data["headers"],
      request_body: truncate_body(request_data["body"]),
      request_body_size: body_size(request_data["body"]),
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(Runlocal.PubSub, "inspect:#{subdomain}", {:new_request, entry})
  end

  defp broadcast_request_updated(subdomain, request_id, payload, start_time) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    update = %{
      id: request_id,
      status: payload["status"],
      response_headers: payload["headers"],
      response_body: truncate_body(payload["body"]),
      response_body_size: payload["body_size"] || body_size(payload["body"]),
      duration_ms: duration_ms
    }

    Phoenix.PubSub.broadcast(Runlocal.PubSub, "inspect:#{subdomain}", {:request_updated, update})
  end

  defp sign_inspect_token(subdomain) do
    Phoenix.Token.sign(RunlocalWeb.Endpoint, "inspect", subdomain)
  end

  defp truncate_body(nil), do: nil
  defp truncate_body(body) when byte_size(body) <= @preview_bytes, do: body
  defp truncate_body(body), do: binary_part(body, 0, @preview_bytes)

  defp body_size(nil), do: 0
  defp body_size(body), do: byte_size(body)

  @impl true
  def terminate(_reason, socket) do
    if subdomain = socket.assigns[:subdomain] do
      # Guarded: if a reconnect already took this subdomain over, the row
      # belongs to the replacement and must survive this channel's exit.
      Runlocal.Registry.unregister(subdomain, self())
      Runlocal.RateLimiter.cleanup(subdomain)
      Runlocal.BandwidthLimiter.cleanup(subdomain)
    end

    :ok
  end
end
