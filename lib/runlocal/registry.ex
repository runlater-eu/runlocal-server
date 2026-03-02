defmodule Runlocal.Registry do
  @table :tunnel_registry

  def init do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
  end

  def register(subdomain, channel_pid, client_ip \\ nil) do
    inspect_token = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

    :ets.insert(@table, {subdomain, %{
      channel_pid: channel_pid,
      created_at: DateTime.utc_now(),
      client_ip: client_ip,
      inspect_token: inspect_token
    }})

    inspect_token
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

  def count_by_ip(nil), do: 0

  def count_by_ip(ip) do
    match_spec = [
      {{:_, %{client_ip: :"$1"}}, [{:==, :"$1", ip}], [true]}
    ]

    :ets.select_count(@table, match_spec)
  end
end
