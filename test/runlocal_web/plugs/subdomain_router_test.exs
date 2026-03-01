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
            send(caller_pid, {:tunnel_response, request_id, %{
              "status" => 200,
              "headers" => [],
              "body" => "ok"
            }})
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
end
