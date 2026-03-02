defmodule RunlocalWeb.TunnelChannelTest do
  use RunlocalWeb.ChannelCase

  setup do
    # Use a unique IP per test to avoid hitting the per-IP tunnel limit
    unique_ip = "10.0.0.#{System.unique_integer([:positive]) |> rem(255)}"

    {:ok, _, socket} =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: unique_ip})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    %{socket: socket}
  end

  test "join assigns a subdomain and pushes tunnel_created with inspect_token", %{socket: socket} do
    assert socket.assigns.subdomain =~ ~r/^[a-z]+-[a-z]+$/
    assert_push "tunnel_created", %{"url" => url, "subdomain" => subdomain, "inspect_token" => token}
    assert subdomain == socket.assigns.subdomain
    assert url =~ subdomain
    assert is_binary(token) and byte_size(token) > 0
  end

  test "subdomain is registered in registry", %{socket: socket} do
    subdomain = socket.assigns.subdomain
    result = Runlocal.Registry.lookup(subdomain)
    assert result != nil
    assert result.channel_pid == socket.channel_pid
  end

  test "http_response resolves pending request", %{socket: socket} do
    request_id = "test-req-123"

    send(socket.channel_pid, {:http_request, request_id, %{"method" => "GET", "path" => "/"}, self()})

    assert_push "http_request", %{"request_id" => ^request_id, "method" => "GET"}

    push(socket, "http_response", %{
      "request_id" => request_id,
      "status" => 200,
      "headers" => [["content-type", "text/plain"]],
      "body" => "hello"
    })

    assert_receive {:tunnel_response, ^request_id, %{"status" => 200, "body" => "hello"}}
  end

  test "rejects oversized response body", %{socket: socket} do
    request_id = "test-req-oversized"

    send(socket.channel_pid, {:http_request, request_id, %{"method" => "GET", "path" => "/"}, self()})
    assert_push "http_request", %{"request_id" => ^request_id}

    large_body = String.duplicate("x", 10_000_001)

    push(socket, "http_response", %{
      "request_id" => request_id,
      "status" => 200,
      "headers" => [],
      "body" => large_body
    })

    assert_receive {:tunnel_response, ^request_id, %{"status" => 502, "body" => "Response too large"}}
  end

  test "leave unregisters subdomain", %{socket: socket} do
    subdomain = socket.assigns.subdomain
    assert Runlocal.Registry.lookup(subdomain) != nil

    Process.unlink(socket.channel_pid)
    close(socket)
    Process.sleep(50)

    assert Runlocal.Registry.lookup(subdomain) == nil
  end

  test "rejects join when IP has too many tunnels" do
    ip = "10.99.99.99"

    # Register 5 tunnels for this IP
    for i <- 1..5 do
      Runlocal.Registry.register("limit-test-#{i}", self(), ip)
    end

    result =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: ip})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    assert {:error, %{reason: "too_many_tunnels"}} = result

    # Cleanup
    for i <- 1..5 do
      Runlocal.Registry.unregister("limit-test-#{i}")
    end
  end
end
