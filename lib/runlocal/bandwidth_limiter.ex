defmodule Runlocal.BandwidthLimiter do
  @table :tunnel_bandwidth
  @max_bytes_per_second 50_000_000
  @window_ms 1_000

  def init do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
  end

  def allow?(subdomain, bytes) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, subdomain) do
      [{^subdomain, used, window_start}] ->
        if now - window_start > @window_ms do
          :ets.insert(@table, {subdomain, bytes, now})
          true
        else
          new_used = used + bytes
          if new_used > @max_bytes_per_second do
            false
          else
            :ets.insert(@table, {subdomain, new_used, window_start})
            true
          end
        end

      [] ->
        :ets.insert(@table, {subdomain, bytes, now})
        true
    end
  end

  def cleanup(subdomain) do
    :ets.delete(@table, subdomain)
  end
end
