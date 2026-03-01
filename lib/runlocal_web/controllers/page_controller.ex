defmodule RunlocalWeb.PageController do
  use RunlocalWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def privacy(conn, _params) do
    conn
    |> assign(:page_title, "Privacy Policy")
    |> render(:privacy)
  end

  def dpa(conn, _params) do
    conn
    |> assign(:page_title, "Data Processing Agreement")
    |> render(:dpa)
  end
end
