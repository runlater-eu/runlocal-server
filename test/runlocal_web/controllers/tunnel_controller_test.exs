defmodule RunlocalWeb.TunnelControllerTest do
  use RunlocalWeb.ConnCase

  test "returns 404 for unknown subdomain" do
    conn =
      build_conn(:get, "/hello")
      |> Map.put(:host, "nonexistent.localhost")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    assert conn.status == 404
    assert conn.resp_body =~ "Tunnel not found"
  end

  test "proxies request through tunnel" do
    test_pid = self()

    channel_pid =
      spawn(fn ->
        receive do
          {:http_request, request_id, request_data, caller_pid} ->
            send(test_pid, {:got_request, request_data})

            send(caller_pid, {:tunnel_response, request_id, %{
              "status" => 200,
              "headers" => [["content-type", "application/json"]],
              "body" => ~s({"ok":true})
            }})
        end
      end)

    Runlocal.Registry.register("proxy-test", channel_pid)

    conn =
      build_conn(:get, "/api/test")
      |> Map.put(:host, "proxy-test.localhost")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    assert conn.status == 200
    assert conn.resp_body == ~s({"ok":true})

    assert_receive {:got_request, %{"method" => "GET", "path" => "/api/test"}}

    Runlocal.Registry.unregister("proxy-test")
  end

  test "returns 429 when rate limited" do
    channel_pid =
      spawn(fn ->
        receive do
          _ -> :ok
        after
          5000 -> :ok
        end
      end)

    Runlocal.Registry.register("rate-test", channel_pid)

    # Exhaust the token bucket
    for _ <- 1..10 do
      assert Runlocal.RateLimiter.allow?("rate-test")
    end

    conn =
      build_conn(:get, "/")
      |> Map.put(:host, "rate-test.localhost")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    assert conn.status == 429
    assert conn.resp_body =~ "Too many requests"

    Runlocal.RateLimiter.cleanup("rate-test")
    Runlocal.Registry.unregister("rate-test")
  end
end
