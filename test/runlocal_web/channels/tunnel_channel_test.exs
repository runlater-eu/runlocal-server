defmodule RunlocalWeb.TunnelChannelTest do
  use RunlocalWeb.ChannelCase

  setup do
    {:ok, _, socket} =
      RunlocalWeb.TunnelSocket
      |> socket()
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    %{socket: socket}
  end

  test "join assigns a subdomain and pushes tunnel_created", %{socket: socket} do
    assert socket.assigns.subdomain =~ ~r/^[a-z]+-[a-z]+$/
    assert_push "tunnel_created", %{"url" => url, "subdomain" => subdomain}
    assert subdomain == socket.assigns.subdomain
    assert url =~ subdomain
  end

  test "subdomain is registered in registry", %{socket: socket} do
    subdomain = socket.assigns.subdomain
    result = Runlocal.Registry.lookup(subdomain)
    assert result != nil
    assert result.channel_pid == socket.channel_pid
  end

  test "http_response resolves pending request", %{socket: socket} do
    request_id = "test-req-123"

    # Simulate an http_request arriving
    send(socket.channel_pid, {:http_request, request_id, %{"method" => "GET", "path" => "/"}, self()})

    # The channel should push the request to the client
    assert_push "http_request", %{"request_id" => ^request_id, "method" => "GET"}

    # Client sends response
    push(socket, "http_response", %{
      "request_id" => request_id,
      "status" => 200,
      "headers" => [["content-type", "text/plain"]],
      "body" => "hello"
    })

    # We should receive the tunnel response
    assert_receive {:tunnel_response, ^request_id, %{"status" => 200, "body" => "hello"}}
  end

  test "leave unregisters subdomain", %{socket: socket} do
    subdomain = socket.assigns.subdomain
    assert Runlocal.Registry.lookup(subdomain) != nil

    Process.unlink(socket.channel_pid)
    close(socket)
    # Give it a moment to process the terminate callback
    Process.sleep(50)

    assert Runlocal.Registry.lookup(subdomain) == nil
  end
end
