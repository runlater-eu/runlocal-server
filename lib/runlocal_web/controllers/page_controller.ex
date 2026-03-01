defmodule RunlocalWeb.PageController do
  use RunlocalWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
