defmodule Runlocal.RateLimiter do
  @table :tunnel_rate_limiter
  @max_tokens 10
  @refill_rate 10

  def init do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
  end

  def allow?(subdomain) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, subdomain) do
      [{^subdomain, tokens, last_time}] ->
        elapsed_ms = now - last_time
        refill = elapsed_ms / 1000.0 * @refill_rate
        new_tokens = min(@max_tokens, tokens + refill)

        if new_tokens >= 1.0 do
          :ets.insert(@table, {subdomain, new_tokens - 1.0, now})
          true
        else
          :ets.insert(@table, {subdomain, new_tokens, now})
          false
        end

      [] ->
        :ets.insert(@table, {subdomain, @max_tokens - 1.0, now})
        true
    end
  end

  def cleanup(subdomain) do
    :ets.delete(@table, subdomain)
  end
end
