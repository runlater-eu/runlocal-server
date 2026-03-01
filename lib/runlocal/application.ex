defmodule Runlocal.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Runlocal.Registry.init()
    Runlocal.RateLimiter.init()
    Runlocal.IpBlocklist.init()
    Runlocal.BandwidthLimiter.init()

    children = [
      RunlocalWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:runlocal, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Runlocal.PubSub},
      # Start a worker by calling: Runlocal.Worker.start_link(arg)
      # {Runlocal.Worker, arg},
      # Start to serve requests, typically the last entry
      RunlocalWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Runlocal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RunlocalWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
