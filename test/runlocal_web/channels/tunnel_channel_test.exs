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

  test "decodes base64 response body when client advertises binary-bodies cap" do
    unique_ip = "10.0.1.#{System.unique_integer([:positive]) |> rem(255)}"
    caps = MapSet.new(["binary-bodies"])

    {:ok, _, socket} =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: unique_ip, caps: caps})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    request_id = "test-req-binary"
    binary_body = <<0, 128, 196, 171, 255>>

    send(socket.channel_pid, {:http_request, request_id, %{"method" => "GET", "path" => "/", "body" => ""}, self()})

    assert_push "http_request", %{"request_id" => ^request_id, "body_encoding" => "base64"}

    push(socket, "http_response", %{
      "request_id" => request_id,
      "status" => 200,
      "headers" => [["content-type", "application/octet-stream"]],
      "body" => Base.encode64(binary_body),
      "body_encoding" => "base64"
    })

    assert_receive {:tunnel_response, ^request_id, %{"status" => 200, "body" => ^binary_body}}
  end

  test "base64-encodes outbound request body for clients that advertise the cap" do
    unique_ip = "10.0.2.#{System.unique_integer([:positive]) |> rem(255)}"
    caps = MapSet.new(["binary-bodies"])

    {:ok, _, socket} =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: unique_ip, caps: caps})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    request_id = "test-req-bin-out"
    binary_body = <<0, 128, 196, 171, 255>>

    send(socket.channel_pid, {:http_request, request_id, %{"method" => "POST", "path" => "/", "body" => binary_body}, self()})

    expected_b64 = Base.encode64(binary_body)
    assert_push "http_request", %{"request_id" => ^request_id, "body" => ^expected_b64, "body_encoding" => "base64"}
  end

  test "leaves request body raw when client does not advertise the cap", %{socket: socket} do
    request_id = "test-req-no-cap"
    body = "plain text"

    send(socket.channel_pid, {:http_request, request_id, %{"method" => "POST", "path" => "/", "body" => body}, self()})

    assert_push "http_request", %{"request_id" => ^request_id, "body" => ^body} = pushed
    refute Map.has_key?(pushed, "body_encoding")
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
