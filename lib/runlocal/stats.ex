defmodule Runlocal.Stats do
  use GenServer

  @ets_table :stats_counters
  @dets_table :stats_daily
  @flush_interval_ms 60_000

  # --- Public API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def track_tunnel(ip) do
    date = Date.utc_today() |> Date.to_iso8601()
    :ets.update_counter(@ets_table, {:tunnels, date}, 1, {{:tunnels, date}, 0})

    if ip do
      hashed = hash_ip(ip)
      :ets.insert(@ets_table, {{:ip, date, hashed}, true})
    end
  end

  def track_request do
    date = Date.utc_today() |> Date.to_iso8601()
    :ets.update_counter(@ets_table, {:requests, date}, 1, {{:requests, date}, 0})
  end

  def summary do
    GenServer.call(__MODULE__, :summary)
  end

  # --- GenServer ---

  @impl true
  def init(_) do
    :ets.new(@ets_table, [:named_table, :public, :set, write_concurrency: true])

    dets_path = Application.get_env(:runlocal, :stats_path, "data/stats.dets") |> to_charlist()
    File.mkdir_p!(Path.dirname(to_string(dets_path)))
    {:ok, @dets_table} = :dets.open_file(@dets_table, file: dets_path, type: :set)

    salt = load_or_create_salt(dets_path)
    :persistent_term.put(:stats_ip_salt, salt)

    schedule_flush()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:summary, _from, state) do
    today = Date.utc_today() |> Date.to_iso8601()

    today_stats = %{
      tunnels: ets_counter({:tunnels, today}),
      requests: ets_counter({:requests, today}),
      unique_ips: count_unique_ips(today),
      active_tunnels: :ets.info(:tunnel_registry, :size)
    }

    history =
      :dets.foldl(
        fn {{:daily, date}, stats}, acc -> Map.put(acc, date, stats)
           _, acc -> acc
        end,
        %{},
        @dets_table
      )

    {:reply, %{today: today_stats, history: history}, state}
  end

  @impl true
  def handle_info(:flush, state) do
    flush_to_dets()
    schedule_flush()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    flush_to_dets()
    :dets.close(@dets_table)
    :ok
  end

  # --- Internals ---

  defp flush_to_dets do
    today = Date.utc_today() |> Date.to_iso8601()

    stats = %{
      tunnels: ets_counter({:tunnels, today}),
      requests: ets_counter({:requests, today}),
      unique_ips: count_unique_ips(today)
    }

    :dets.insert(@dets_table, {{:daily, today}, stats})
  end

  defp ets_counter(key) do
    case :ets.lookup(@ets_table, key) do
      [{^key, count}] -> count
      [] -> 0
    end
  end

  defp count_unique_ips(date) do
    :ets.select_count(@ets_table, [
      {{{:ip, :"$1", :_}, :_}, [{:==, :"$1", date}], [true]}
    ])
  end

  defp hash_ip(ip) do
    salt = :persistent_term.get(:stats_ip_salt)
    :crypto.hash(:sha256, salt <> ip) |> Base.encode16(case: :lower) |> binary_part(0, 16)
  end

  defp load_or_create_salt(dets_path) do
    salt_path = to_string(dets_path) |> Path.rootname() |> Kernel.<>(".salt")

    case File.read(salt_path) do
      {:ok, salt} when byte_size(salt) == 32 -> salt
      _ ->
        salt = :crypto.strong_rand_bytes(32)
        File.write!(salt_path, salt)
        salt
    end
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end
end
