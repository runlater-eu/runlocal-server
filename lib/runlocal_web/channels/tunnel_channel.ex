defmodule RunlocalWeb.TunnelChannel do
  use Phoenix.Channel

  @two_hours_ms 2 * 60 * 60 * 1000

  @impl true
  def join("tunnel:connect", _payload, socket) do
    subdomain = Runlocal.Subdomain.generate()
    Runlocal.Registry.register(subdomain, self())
    Process.send_after(self(), :ttl_expired, @two_hours_ms)

    base_domain = Application.get_env(:runlocal, :base_domain, "localhost")

    url =
      if base_domain == "localhost" do
        "http://#{subdomain}.localhost:4000"
      else
        "https://#{subdomain}.#{base_domain}"
      end

    socket =
      socket
      |> assign(:subdomain, subdomain)
      |> assign(:pending_requests, %{})

    send(self(), {:after_join, url})
    {:ok, socket}
  end

  @impl true
  def handle_info({:after_join, url}, socket) do
    push(socket, "tunnel_created", %{"url" => url, "subdomain" => socket.assigns.subdomain})
    {:noreply, socket}
  end

  def handle_info({:http_request, request_id, request_data, caller_pid}, socket) do
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

    case Map.pop(socket.assigns.pending_requests, request_id) do
      {nil, _} ->
        {:noreply, socket}

      {caller_pid, remaining} ->
        send(caller_pid, {:tunnel_response, request_id, payload})
        {:noreply, assign(socket, :pending_requests, remaining)}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if subdomain = socket.assigns[:subdomain] do
      Runlocal.Registry.unregister(subdomain)
    end

    :ok
  end
end
