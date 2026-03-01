defmodule Runlocal.Registry do
  @table :tunnel_registry

  def init do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
  end

  def register(subdomain, channel_pid) do
    :ets.insert(@table, {subdomain, %{channel_pid: channel_pid, created_at: DateTime.utc_now()}})
  end

  def lookup(subdomain) do
    case :ets.lookup(@table, subdomain) do
      [{^subdomain, data}] -> data
      [] -> nil
    end
  end

  def unregister(subdomain) do
    :ets.delete(@table, subdomain)
  end
end
