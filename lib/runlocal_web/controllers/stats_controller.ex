defmodule RunlocalWeb.StatsController do
  use RunlocalWeb, :controller

  def index(conn, _params) do
    stats = Runlocal.Stats.summary()

    conn
    |> assign(:page_title, "Stats")
    |> assign(:stats, stats)
    |> render(:index)
  end
end
