defmodule RunlocalWeb.TunnelChannelTest do
  use RunlocalWeb.ChannelCase

  # Spread the counter across three octets. Folding it into a single octet with
  # `rem(255)` collided often enough to trip the per-IP tunnel limit and fail an
  # unrelated test.
  defp unique_ip do
    n = System.unique_integer([:positive])
    "10.#{rem(div(n, 65_536), 256)}.#{rem(div(n, 256), 256)}.#{rem(n, 256)}"
  end

  setup do
    unique_ip = unique_ip()

    {:ok, _, socket} =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: unique_ip})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    %{socket: socket}
  end

  test "join assigns a subdomain and pushes tunnel_created with inspect_token", %{socket: socket} do
    assert socket.assigns.subdomain =~ ~r/^[a-z]+-[a-z]+$/

    assert_push "tunnel_created", %{
      "url" => url,
      "subdomain" => subdomain,
      "inspect_token" => token
    }

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

    send(
      socket.channel_pid,
      {:http_request, request_id, %{"method" => "GET", "path" => "/"}, self()}
    )

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
    unique_ip = unique_ip()
    caps = MapSet.new(["binary-bodies"])

    {:ok, _, socket} =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: unique_ip, caps: caps})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    request_id = "test-req-binary"
    binary_body = <<0, 128, 196, 171, 255>>

    send(
      socket.channel_pid,
      {:http_request, request_id, %{"method" => "GET", "path" => "/", "body" => ""}, self()}
    )

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
    unique_ip = unique_ip()
    caps = MapSet.new(["binary-bodies"])

    {:ok, _, socket} =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: unique_ip, caps: caps})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    request_id = "test-req-bin-out"
    binary_body = <<0, 128, 196, 171, 255>>

    send(
      socket.channel_pid,
      {:http_request, request_id, %{"method" => "POST", "path" => "/", "body" => binary_body},
       self()}
    )

    expected_b64 = Base.encode64(binary_body)

    assert_push "http_request", %{
      "request_id" => ^request_id,
      "body" => ^expected_b64,
      "body_encoding" => "base64"
    }
  end

  test "leaves request body raw when client does not advertise the cap", %{socket: socket} do
    request_id = "test-req-no-cap"
    body = "plain text"

    send(
      socket.channel_pid,
      {:http_request, request_id, %{"method" => "POST", "path" => "/", "body" => body}, self()}
    )

    assert_push "http_request", %{"request_id" => ^request_id, "body" => ^body} = pushed
    refute Map.has_key?(pushed, "body_encoding")
  end

  test "rejects oversized response body", %{socket: socket} do
    request_id = "test-req-oversized"

    send(
      socket.channel_pid,
      {:http_request, request_id, %{"method" => "GET", "path" => "/"}, self()}
    )

    assert_push "http_request", %{"request_id" => ^request_id}

    large_body = String.duplicate("x", 10_000_001)

    push(socket, "http_response", %{
      "request_id" => request_id,
      "status" => 200,
      "headers" => [],
      "body" => large_body
    })

    assert_receive {:tunnel_response, ^request_id,
                    %{"status" => 502, "body" => "Response too large"}}
  end

  test "tunnel_created advertises what the server can handle", %{socket: _socket} do
    # Clients must not send streaming frames to a server without handlers for
    # them, so the server states its capabilities up front.
    assert_push "tunnel_created", %{"caps" => caps}
    assert "stream" in caps
  end

  test "streamed response frames reach the waiting request", %{socket: socket} do
    request_id = "stream-req-1"

    send(
      socket.channel_pid,
      {:http_request, request_id, %{"method" => "GET", "path" => "/"}, self()}
    )

    assert_push "http_request", %{"request_id" => ^request_id}

    push(socket, "http_response_start", %{
      "request_id" => request_id,
      "status" => 200,
      "headers" => [["content-type", "text/event-stream"]]
    })

    assert_receive {:tunnel_response_start, ^request_id, 200,
                    [["content-type", "text/event-stream"]]}

    push(socket, "http_response_chunk", %{
      "request_id" => request_id,
      "body" => Base.encode64("tick"),
      "body_encoding" => "base64"
    })

    assert_receive {:tunnel_response_chunk, ^request_id, "tick"}

    push(socket, "http_response_end", %{"request_id" => request_id})
    assert_receive {:tunnel_response_end, ^request_id}
  end

  test "a streamed response is not subject to the single-frame size cap", %{socket: socket} do
    request_id = "stream-req-2"
    chunk = String.duplicate("x", 1_000_000)

    send(
      socket.channel_pid,
      {:http_request, request_id, %{"method" => "GET", "path" => "/"}, self()}
    )

    assert_push "http_request", %{"request_id" => ^request_id}

    push(socket, "http_response_start", %{"request_id" => request_id, "status" => 200})
    assert_receive {:tunnel_response_start, ^request_id, 200, _}

    for _ <- 1..12 do
      push(socket, "http_response_chunk", %{
        "request_id" => request_id,
        "body" => Base.encode64(chunk),
        "body_encoding" => "base64"
      })
    end

    push(socket, "http_response_end", %{"request_id" => request_id})

    # 12 MB delivered, where a single http_response frame would have been
    # replaced by a 502 past 10 MB.
    assert_receive {:tunnel_response_end, ^request_id}
    refute_receive {:tunnel_response, ^request_id, %{"status" => 502}}
  end

  test "streamed response frames for an unknown request are ignored", %{socket: socket} do
    push(socket, "http_response_chunk", %{"request_id" => "ghost", "body" => ""})
    push(socket, "http_response_end", %{"request_id" => "ghost"})
    refute_receive {:tunnel_response_end, "ghost"}
  end

  test "a large request body is pushed to the client as chunks", %{socket: socket} do
    request_id = "up-1"

    send(
      socket.channel_pid,
      {:http_request_start, request_id, %{"method" => "POST", "path" => "/u", "body" => ""},
       self()}
    )

    assert_push "http_request_start", %{"request_id" => ^request_id, "body_streaming" => true}

    send(socket.channel_pid, {:http_request_chunk, request_id, "part"})
    assert_push "http_request_chunk", %{"request_id" => ^request_id, "body" => encoded}
    assert Base.decode64!(encoded) == "part"

    send(socket.channel_pid, {:http_request_end, request_id})
    assert_push "http_request_end", %{"request_id" => ^request_id}
  end

  test "cancel tells the client to abandon the request", %{socket: socket} do
    request_id = "cancel-1"

    send(
      socket.channel_pid,
      {:http_request, request_id, %{"method" => "GET", "path" => "/"}, self()}
    )

    assert_push "http_request", %{"request_id" => ^request_id}

    send(socket.channel_pid, {:cancel_request, request_id})
    assert_push "http_cancel", %{"request_id" => ^request_id}

    # The request is forgotten, so a late response is dropped rather than
    # delivered to a caller that has already given up.
    push(socket, "http_response", %{"request_id" => request_id, "status" => 200, "body" => "late"})

    refute_receive {:tunnel_response, ^request_id, _}
  end

  test "a reconnect from the same IP takes the subdomain back" do
    ip = unique_ip()
    subdomain = "takeover-#{System.unique_integer([:positive])}"

    old = spawn(fn -> Process.sleep(:infinity) end)
    Runlocal.Registry.register(subdomain, old, ip)

    assert {:ok, {:took_over, ^old}} = Runlocal.Registry.claim(subdomain, self(), ip)
    assert Runlocal.Registry.lookup(subdomain).channel_pid == self()

    # The displaced owner's guarded unregister must not remove the new claim.
    assert Runlocal.Registry.unregister(subdomain, old) == 0
    assert Runlocal.Registry.lookup(subdomain).channel_pid == self()

    Runlocal.Registry.unregister(subdomain)
    Process.exit(old, :kill)
  end

  test "client caps are recorded in the registry for the proxy to read" do
    unique_ip = unique_ip()
    caps = MapSet.new(["binary-bodies", "stream"])

    {:ok, _, socket} =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: unique_ip, caps: caps})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    entry = Runlocal.Registry.lookup(socket.assigns.subdomain)
    assert Runlocal.Registry.supports?(entry, "stream")
    refute Runlocal.Registry.supports?(entry, "nope")
  end

  test "leave unregisters subdomain", %{socket: socket} do
    subdomain = socket.assigns.subdomain
    assert Runlocal.Registry.lookup(subdomain) != nil

    Process.unlink(socket.channel_pid)
    close(socket)
    Process.sleep(50)

    assert Runlocal.Registry.lookup(subdomain) == nil
  end

  test "rejects a second anonymous tunnel from the same IP" do
    ip = "10.99.99.99"

    # A single existing tunnel from this IP is enough to block anonymous clients
    Runlocal.Registry.register("limit-test-1", self(), ip)

    result =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: ip})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    assert {:error, %{reason: "too_many_tunnels"}} = result

    Runlocal.Registry.unregister("limit-test-1")
  end

  test "registered (api_key) clients may open more than one tunnel per IP" do
    ip = "10.99.98.98"

    # One tunnel already open from this IP — would block an anonymous client
    Runlocal.Registry.register("reg-test-existing", self(), ip)

    {:ok, _, socket} =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: ip, api_key: "valid-key"})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    assert is_binary(socket.assigns.subdomain)

    Runlocal.Registry.unregister("reg-test-existing")
  end

  test "rejects anonymous tunnels from blocklisted networks" do
    # 198.51.100.10 maps to a blocked ASN via :geoip_static in config/test.exs
    result =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: "198.51.100.10"})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    assert {:error, %{reason: "blocked_network"}} = result
  end

  test "api_key does not bypass the network blocklist outside :runlater mode" do
    result =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: "198.51.100.10", api_key: "some-key"})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    assert {:error, %{reason: "blocked_network"}} = result
  end

  test "allows tunnels from networks that are not blocklisted" do
    {:ok, _, socket} =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: "198.51.100.20"})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    assert is_binary(socket.assigns.subdomain)
  end

  test "rejects a registered client only once it hits the higher per-IP limit" do
    ip = "10.99.97.97"

    for i <- 1..5 do
      Runlocal.Registry.register("reg-limit-#{i}", self(), ip)
    end

    result =
      RunlocalWeb.TunnelSocket
      |> socket(%{}, %{client_ip: ip, api_key: "valid-key"})
      |> subscribe_and_join(RunlocalWeb.TunnelChannel, "tunnel:connect")

    assert {:error, %{reason: "too_many_tunnels"}} = result

    for i <- 1..5 do
      Runlocal.Registry.unregister("reg-limit-#{i}")
    end
  end
end
