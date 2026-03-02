defmodule RunlocalWeb.PageControllerTest do
  use RunlocalWeb.ConnCase

  describe "landing_page disabled" do
    setup do
      original = Application.get_env(:runlocal, :landing_page)
      Application.put_env(:runlocal, :landing_page, false)
      on_exit(fn -> Application.put_env(:runlocal, :landing_page, original) end)
    end

    test "GET / shows status page", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Running"
      assert html_response(conn, 200) =~ "active"
    end

    test "GET /getting-started redirects to /", %{conn: conn} do
      conn = get(conn, ~p"/getting-started")
      assert redirected_to(conn) == "/"
    end

    test "GET /privacy redirects to /", %{conn: conn} do
      conn = get(conn, ~p"/privacy")
      assert redirected_to(conn) == "/"
    end

    test "GET /legal/dpa redirects to /", %{conn: conn} do
      conn = get(conn, ~p"/legal/dpa")
      assert redirected_to(conn) == "/"
    end
  end

  describe "landing_page enabled" do
    setup do
      original = Application.get_env(:runlocal, :landing_page)
      Application.put_env(:runlocal, :landing_page, true)
      on_exit(fn -> Application.put_env(:runlocal, :landing_page, original) end)
    end

    test "GET / shows marketing home", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Expose localhost"
      assert html_response(conn, 200) =~ "npx runlocal 3000"
    end

    test "GET /getting-started renders", %{conn: conn} do
      conn = get(conn, ~p"/getting-started")
      assert html_response(conn, 200) =~ "Getting Started"
    end

    test "GET /privacy renders", %{conn: conn} do
      conn = get(conn, ~p"/privacy")
      assert html_response(conn, 200) =~ "Privacy"
    end
  end
end
