defmodule Runlocal.IpBlocklist do
  @table :ip_blocklist

  def init do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
  end

  def blocked?(nil), do: false

  def blocked?(ip) do
    :ets.member(@table, ip)
  end

  def block(ip) do
    :ets.insert(@table, {ip, DateTime.utc_now()})
    :ok
  end

  def unblock(ip) do
    :ets.delete(@table, ip)
    :ok
  end

  def list do
    :ets.tab2list(@table)
    |> Enum.map(fn {ip, blocked_at} -> %{ip: ip, blocked_at: blocked_at} end)
  end
end
