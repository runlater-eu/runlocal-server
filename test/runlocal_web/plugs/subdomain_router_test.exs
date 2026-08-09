defmodule RunlocalWeb.Plugs.SubdomainRouterTest do
  use RunlocalWeb.ConnCase

  test "passes through when no subdomain (localhost)" do
    conn =
      build_conn()
      |> Map.put(:host, "localhost")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    refute conn.halted
  end

  test "extracts subdomain and halts conn" do
    # Spawn a process that responds to http_request immediately
    responder =
      spawn(fn ->
        receive do
          {:http_request, request_id, _request_data, caller_pid} ->
            send(
              caller_pid,
              {:tunnel_response, request_id,
               %{
                 "status" => 200,
                 "headers" => [],
                 "body" => "ok"
               }}
            )
        end
      end)

    Runlocal.Registry.register("plug-test", responder)

    conn =
      build_conn(:get, "/hello")
      |> Map.put(:host, "plug-test.localhost")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    assert conn.halted
    assert conn.status == 200
    Runlocal.Registry.unregister("plug-test")
  end

  test "returns 404 for unknown subdomain" do
    conn =
      build_conn(:get, "/")
      |> Map.put(:host, "unknown-sub.localhost")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    assert conn.halted
    assert conn.status == 404
  end

  test "blocks tunnel visitors from blocklisted countries" do
    # 198.51.100.10 maps to a blocked country via :geoip_static in config/test.exs
    conn =
      build_conn(:get, "/")
      |> Map.put(:host, "geo-test.localhost")
      |> put_req_header("x-forwarded-for", "198.51.100.10")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    assert conn.halted
    assert conn.status == 403
  end

  test "lets visitors from non-blocked countries through" do
    conn =
      build_conn(:get, "/")
      |> Map.put(:host, "geo-test.localhost")
      |> put_req_header("x-forwarded-for", "198.51.100.20")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    # No tunnel registered, so this falls through to the 404 — not a 403
    assert conn.status == 404
  end

  test "country blocking does not apply to the base domain" do
    conn =
      build_conn(:get, "/")
      |> Map.put(:host, "localhost")
      |> put_req_header("x-forwarded-for", "198.51.100.10")
      |> RunlocalWeb.Plugs.SubdomainRouter.call([])

    refute conn.halted
  end
end
