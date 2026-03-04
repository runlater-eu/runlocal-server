defmodule RunlocalWeb.Router do
  use RunlocalWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RunlocalWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RunlocalWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/getting-started", PageController, :getting_started
    get "/privacy", PageController, :privacy
    get "/legal/dpa", PageController, :dpa
    get "/legal/terms", PageController, :terms
    get "/stats", StatsController, :index
    live "/inspect/:subdomain/:token", InspectorLive
  end

end
