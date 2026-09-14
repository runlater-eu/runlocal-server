defmodule Runlocal.Registry do
  @table :tunnel_registry

  def init do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
  end

  def register(subdomain, channel_pid, client_ip \\ nil) do
    :ets.insert(@table, {subdomain, entry(channel_pid, client_ip)})
  end

  @doc """
  Claims `subdomain` for `channel_pid`, returning what had to happen to get it.

  A registration is only meaningful while its channel process is alive. Two
  cases look like a collision but are really a stale row:

    * the owning channel died without `terminate/2` running, so nothing ever
      removed it from the table; and
    * the owner is still alive but its client is gone — a half-open socket the
      server will not notice until the channel heartbeat times out, up to a
      minute later. Every reconnect in that window would otherwise be pushed
      onto a random subdomain while the real hostname 404s.

  The second case is recognised by the newcomer sharing the previous owner's
  client IP: same machine, same tunnel, new socket. It takes over, and the
  caller is expected to stop the process named in `{:took_over, pid}`.

  A live owner on a different IP is a genuine second tunnel and gets `:taken`.
  """
  def claim(subdomain, channel_pid, client_ip \\ nil) do
    if :ets.insert_new(@table, {subdomain, entry(channel_pid, client_ip)}) do
      {:ok, :claimed}
    else
      resolve_conflict(subdomain, channel_pid, client_ip)
    end
  end

  defp resolve_conflict(subdomain, channel_pid, client_ip) do
    case lookup(subdomain) do
      # Freed between insert_new/2 and the read — try once more.
      nil ->
        claim(subdomain, channel_pid, client_ip)

      %{channel_pid: ^channel_pid} ->
        {:ok, :claimed}

      %{channel_pid: owner, client_ip: owner_ip} ->
        cond do
          not Process.alive?(owner) ->
            register(subdomain, channel_pid, client_ip)
            {:ok, {:evicted_stale, owner}}

          not is_nil(client_ip) and owner_ip == client_ip ->
            register(subdomain, channel_pid, client_ip)
            {:ok, {:took_over, owner}}

          true ->
            {:taken, owner}
        end
    end
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

  @doc """
  Removes `subdomain` only while `channel_pid` still owns it.

  A channel that lost the subdomain to a reconnecting replacement still runs
  `terminate/2` afterwards; an unguarded delete there would take the live
  registration with it.
  """
  def unregister(subdomain, channel_pid) do
    match_spec = [
      {{subdomain, %{channel_pid: :"$1"}}, [{:==, :"$1", channel_pid}], [true]}
    ]

    :ets.select_delete(@table, match_spec)
  end

  @doc """
  Records the wire capabilities `channel_pid`'s client negotiated, so that the
  proxy can tell whether a request body may be streamed to it rather than
  buffered. Guarded by pid for the same reason `unregister/2` is.
  """
  def set_caps(subdomain, channel_pid, caps) do
    case lookup(subdomain) do
      %{channel_pid: ^channel_pid} = entry ->
        :ets.insert(@table, {subdomain, Map.put(entry, :caps, caps)})

      _ ->
        false
    end
  end

  @doc """
  Whether the tunnel client behind this registry entry negotiated `cap`.
  """
  def supports?(%{caps: caps}, cap) when not is_nil(caps), do: MapSet.member?(caps, cap)
  def supports?(_entry, _cap), do: false

  def count_by_ip(nil), do: 0

  def count_by_ip(ip) do
    match_spec = [
      {{:_, %{client_ip: :"$1"}}, [{:==, :"$1", ip}], [true]}
    ]

    :ets.select_count(@table, match_spec)
  end

  defp entry(channel_pid, client_ip) do
    %{
      channel_pid: channel_pid,
      created_at: DateTime.utc_now(),
      client_ip: client_ip,
      caps: nil
    }
  end
end
