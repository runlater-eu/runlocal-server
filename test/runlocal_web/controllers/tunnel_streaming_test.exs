defmodule RunlocalWeb.TunnelStreamingTest do
  use RunlocalWeb.ConnCase

  # Stands in for a tunnel client: answers whatever the proxy sends it with a
  # scripted reply, and reports back to the test what it saw.
  defp fake_client(test_pid, fun) do
    spawn(fn ->
      receive do
        message ->
          send(test_pid, {:client_saw, message})
          fun.(message)
      after
        5_000 -> :ok
      end
    end)
  end

  defp register(subdomain, pid, caps) do
    Runlocal.Registry.register(subdomain, pid, "10.1.1.1")
    if caps, do: Runlocal.Registry.set_caps(subdomain, pid, caps)
    on_exit(fn -> Runlocal.Registry.unregister(subdomain) end)
  end

  defp visit(subdomain, path) do
    build_conn(:get, path)
    |> Map.put(:host, "#{subdomain}.localhost")
    |> RunlocalWeb.Plugs.SubdomainRouter.call([])
  end

  test "streams a chunked response through to the visitor" do
    test_pid = self()

    client =
      fake_client(test_pid, fn {:http_request, request_id, _data, caller} ->
        send(caller, {:tunnel_response_start, request_id, 200, [["content-type", "text/plain"]]})
        send(caller, {:tunnel_response_chunk, request_id, "one "})
        send(caller, {:tunnel_response_chunk, request_id, "two "})
        send(caller, {:tunnel_response_chunk, request_id, "three"})
        send(caller, {:tunnel_response_end, request_id})
      end)

    register("stream-ok", client, MapSet.new(["stream"]))

    conn = visit("stream-ok", "/feed")

    assert conn.status == 200
    assert conn.state == :chunked
    assert conn.resp_body == "one two three"
    assert get_resp_header(conn, "content-type") == ["text/plain"]
  end

  test "a streamed response is not capped at the buffered response limit" do
    test_pid = self()
    chunk = String.duplicate("x", 1_000_000)

    client =
      fake_client(test_pid, fn {:http_request, request_id, _data, caller} ->
        send(caller, {:tunnel_response_start, request_id, 200, []})
        # 15 MB, comfortably past the 10 MB single-frame ceiling.
        for _ <- 1..15, do: send(caller, {:tunnel_response_chunk, request_id, chunk})
        send(caller, {:tunnel_response_end, request_id})
      end)

    register("stream-big", client, MapSet.new(["stream"]))

    conn = visit("stream-big", "/download")

    assert conn.status == 200
    assert byte_size(conn.resp_body) == 15_000_000
  end

  test "drops content-length from a streamed response" do
    test_pid = self()

    client =
      fake_client(test_pid, fn {:http_request, request_id, _data, caller} ->
        headers = [["content-type", "text/plain"], ["content-length", "999"]]
        send(caller, {:tunnel_response_start, request_id, 200, headers})
        send(caller, {:tunnel_response_chunk, request_id, "short"})
        send(caller, {:tunnel_response_end, request_id})
      end)

    register("stream-len", client, MapSet.new(["stream"]))

    conn = visit("stream-len", "/")

    assert get_resp_header(conn, "content-length") == []
    assert conn.resp_body == "short"
  end

  test "strips hop-by-hop headers from a streamed response" do
    test_pid = self()

    client =
      fake_client(test_pid, fn {:http_request, request_id, _data, caller} ->
        headers = [["content-type", "text/plain"], ["connection", "keep-alive"]]
        send(caller, {:tunnel_response_start, request_id, 200, headers})
        send(caller, {:tunnel_response_end, request_id})
      end)

    register("stream-hop", client, MapSet.new(["stream"]))

    conn = visit("stream-hop", "/")

    assert get_resp_header(conn, "connection") == []
  end

  test "keeps every set-cookie header on a streamed response" do
    test_pid = self()

    client =
      fake_client(test_pid, fn {:http_request, request_id, _data, caller} ->
        headers = [
          ["content-type", "text/plain"],
          ["set-cookie", "session=abc; Path=/; HttpOnly"],
          ["set-cookie", "csrf=xyz; Path=/"]
        ]

        send(caller, {:tunnel_response_start, request_id, 200, headers})
        send(caller, {:tunnel_response_end, request_id})
      end)

    register("stream-cookies", client, MapSet.new(["stream"]))

    conn = visit("stream-cookies", "/login")

    assert get_resp_header(conn, "set-cookie") == [
             "session=abc; Path=/; HttpOnly",
             "csrf=xyz; Path=/"
           ]
  end

  test "keeps every set-cookie header on a buffered response" do
    test_pid = self()

    client =
      fake_client(test_pid, fn {:http_request, request_id, _data, caller} ->
        headers = [
          ["Set-Cookie", "session=abc; Path=/; HttpOnly"],
          ["Set-Cookie", "csrf=xyz; Path=/"]
        ]

        send(caller, {:tunnel_response, request_id, %{"status" => 200, "headers" => headers}})
      end)

    register("buffered-cookies", client, nil)

    conn = visit("buffered-cookies", "/login")

    assert get_resp_header(conn, "set-cookie") == [
             "session=abc; Path=/; HttpOnly",
             "csrf=xyz; Path=/"
           ]
  end

  test "an origin header replaces the default instead of duplicating it" do
    test_pid = self()

    client =
      fake_client(test_pid, fn {:http_request, request_id, _data, caller} ->
        headers = [["cache-control", "public, max-age=60"]]
        send(caller, {:tunnel_response, request_id, %{"status" => 200, "headers" => headers}})
      end)

    register("buffered-cache", client, nil)

    conn = visit("buffered-cache", "/")

    assert get_resp_header(conn, "cache-control") == ["public, max-age=60"]
  end

  test "a buffered response still works for clients that do not stream" do
    test_pid = self()

    client =
      fake_client(test_pid, fn {:http_request, request_id, _data, caller} ->
        send(caller, {:tunnel_response, request_id, %{"status" => 201, "body" => "made"}})
      end)

    register("buffered", client, nil)

    conn = visit("buffered", "/")

    assert conn.status == 201
    assert conn.state == :sent
    assert conn.resp_body == "made"
  end

  test "streams a large request body to a client that supports it" do
    test_pid = self()
    body = String.duplicate("a", 2_500_000)

    client =
      spawn(fn ->
        # Head first, then the body in chunks, then the terminator.
        receive do
          {:http_request_start, request_id, data, caller} ->
            send(test_pid, {:head, data})
            received = collect_request_chunks(request_id, 0)
            send(test_pid, {:uploaded, received})
            send(caller, {:tunnel_response, request_id, %{"status" => 200, "body" => "ok"}})
        after
          5_000 -> :ok
        end
      end)

    register("upload-stream", client, MapSet.new(["stream"]))

    conn =
      build_conn(:post, "/upload", body)
      |> Map.put(:host, "upload-stream.localhost")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    assert conn.status == 200
    # The head carries no body — it arrives as chunks.
    assert_receive {:head, %{"method" => "POST", "body" => ""}}
    assert_receive {:uploaded, 2_500_000}, 5_000
  end

  test "rejects an oversized body for a client that cannot stream" do
    client = fake_client(self(), fn _ -> :ok end)
    register("upload-legacy", client, nil)

    conn =
      build_conn(:post, "/upload", String.duplicate("a", 11_000_000))
      |> Map.put(:host, "upload-legacy.localhost")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    assert conn.status == 413
    assert conn.resp_body =~ "Payload too large"
  end

  test "a body under the buffered limit is still sent in one piece" do
    test_pid = self()

    client =
      fake_client(test_pid, fn {:http_request, request_id, _data, caller} ->
        send(caller, {:tunnel_response, request_id, %{"status" => 200, "body" => "ok"}})
      end)

    register("upload-small", client, MapSet.new(["stream"]))

    conn =
      build_conn(:post, "/upload", "tiny")
      |> Map.put(:host, "upload-small.localhost")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    assert conn.status == 200
    assert_receive {:client_saw, {:http_request, _id, %{"body" => "tiny"}, _caller}}
  end

  defp collect_request_chunks(request_id, total) do
    receive do
      {:http_request_chunk, ^request_id, data} ->
        collect_request_chunks(request_id, total + byte_size(data))

      {:http_request_end, ^request_id} ->
        total
    after
      5_000 -> total
    end
  end
end
