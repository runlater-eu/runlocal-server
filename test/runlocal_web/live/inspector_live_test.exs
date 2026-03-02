defmodule RunlocalWeb.InspectorLiveTest do
  use RunlocalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "no active tunnel" do
    test "shows disconnected state when tunnel does not exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/inspect/nonexistent-tunnel")

      assert html =~ "No active tunnel"
      assert html =~ "npx runlocal"
      assert html =~ "Disconnected"
    end
  end

  describe "with active tunnel" do
    setup do
      subdomain = "test-inspector-#{System.unique_integer([:positive])}"
      Runlocal.Registry.register(subdomain, self())

      on_exit(fn ->
        Runlocal.Registry.unregister(subdomain)
      end)

      %{subdomain: subdomain}
    end

    test "shows connected and waiting state", %{conn: conn, subdomain: subdomain} do
      {:ok, _view, html} = live(conn, "/inspect/#{subdomain}")

      assert html =~ "Connected"
      assert html =~ "Waiting for requests"
      assert html =~ subdomain
    end

    test "displays new requests from PubSub", %{conn: conn, subdomain: subdomain} do
      {:ok, view, _html} = live(conn, "/inspect/#{subdomain}")

      entry = %{
        id: "req-123",
        method: "POST",
        path: "/api/webhook",
        query_string: "",
        request_headers: [["content-type", "application/json"]],
        request_body: ~s({"event": "test"}),
        request_body_size: 17,
        timestamp: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(Runlocal.PubSub, "inspect:#{subdomain}", {:new_request, entry})

      html = render(view)

      assert html =~ "POST"
      assert html =~ "/api/webhook"
      refute html =~ "Waiting for requests"
    end

    test "updates request with response data", %{conn: conn, subdomain: subdomain} do
      {:ok, view, _html} = live(conn, "/inspect/#{subdomain}")

      entry = %{
        id: "req-456",
        method: "GET",
        path: "/health",
        query_string: "",
        request_headers: [],
        request_body: nil,
        request_body_size: 0,
        timestamp: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(Runlocal.PubSub, "inspect:#{subdomain}", {:new_request, entry})

      # Verify pending state
      html = render(view)
      assert html =~ "Waiting for response"

      update = %{
        id: "req-456",
        status: 200,
        response_headers: [["content-type", "text/plain"]],
        response_body: "OK",
        response_body_size: 2,
        duration_ms: 42
      }

      Phoenix.PubSub.broadcast(Runlocal.PubSub, "inspect:#{subdomain}", {:request_updated, update})

      html = render(view)
      assert html =~ "200"
      assert html =~ "42ms"
      assert html =~ "OK"
    end

    test "shows disconnected when tunnel process exits", %{conn: conn, subdomain: subdomain} do
      # Register a separate process we can kill
      tunnel_pid = spawn(fn -> Process.sleep(:infinity) end)
      Runlocal.Registry.register(subdomain, tunnel_pid)

      {:ok, view, html} = live(conn, "/inspect/#{subdomain}")
      assert html =~ "Connected"

      # Kill the tunnel process
      Process.exit(tunnel_pid, :kill)
      Process.sleep(50)

      html = render(view)
      assert html =~ "Disconnected"
    end

    test "clear button removes all entries", %{conn: conn, subdomain: subdomain} do
      {:ok, view, _html} = live(conn, "/inspect/#{subdomain}")

      entry = %{
        id: "req-789",
        method: "GET",
        path: "/test",
        query_string: "",
        request_headers: [],
        request_body: nil,
        request_body_size: 0,
        timestamp: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(Runlocal.PubSub, "inspect:#{subdomain}", {:new_request, entry})

      html = render(view)
      assert html =~ "/test"

      html = view |> element("button", "Clear") |> render_click()

      assert html =~ "Waiting for requests"
      refute html =~ "/test"
    end
  end
end
