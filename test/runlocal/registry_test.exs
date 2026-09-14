defmodule Runlocal.RegistryTest do
  use ExUnit.Case, async: true

  test "register and lookup" do
    Runlocal.Registry.register("test-sub", self())
    result = Runlocal.Registry.lookup("test-sub")
    assert result.channel_pid == self()
    assert %DateTime{} = result.created_at
    Runlocal.Registry.unregister("test-sub")
  end

  test "lookup returns nil for unknown subdomain" do
    assert Runlocal.Registry.lookup("nonexistent-sub") == nil
  end

  test "unregister removes entry" do
    Runlocal.Registry.register("remove-me", self())
    assert Runlocal.Registry.lookup("remove-me") != nil
    Runlocal.Registry.unregister("remove-me")
    assert Runlocal.Registry.lookup("remove-me") == nil
  end

  defp dead_pid do
    {pid, ref} = spawn_monitor(fn -> :ok end)
    receive do: ({:DOWN, ^ref, :process, ^pid, _} -> :ok)
    pid
  end

  test "claim takes a free subdomain" do
    assert {:ok, :claimed} = Runlocal.Registry.claim("claim-free", self(), "10.0.0.1")
    assert Runlocal.Registry.lookup("claim-free").channel_pid == self()
    Runlocal.Registry.unregister("claim-free")
  end

  test "claim is idempotent for the current owner" do
    Runlocal.Registry.claim("claim-same", self(), "10.0.0.1")
    assert {:ok, :claimed} = Runlocal.Registry.claim("claim-same", self(), "10.0.0.1")
    Runlocal.Registry.unregister("claim-same")
  end

  test "claim evicts a registration whose channel is dead" do
    Runlocal.Registry.register("claim-stale", dead_pid(), "10.0.0.1")

    assert {:ok, {:evicted_stale, _owner}} =
             Runlocal.Registry.claim("claim-stale", self(), "10.0.0.2")

    assert Runlocal.Registry.lookup("claim-stale").channel_pid == self()
    Runlocal.Registry.unregister("claim-stale")
  end

  test "claim takes over a live registration from the same client IP" do
    owner = spawn(fn -> Process.sleep(:infinity) end)
    Runlocal.Registry.register("claim-reconnect", owner, "10.0.0.7")

    assert {:ok, {:took_over, ^owner}} =
             Runlocal.Registry.claim("claim-reconnect", self(), "10.0.0.7")

    assert Runlocal.Registry.lookup("claim-reconnect").channel_pid == self()
    Runlocal.Registry.unregister("claim-reconnect")
    Process.exit(owner, :kill)
  end

  test "claim refuses a live registration held from a different IP" do
    owner = spawn(fn -> Process.sleep(:infinity) end)
    Runlocal.Registry.register("claim-taken", owner, "10.0.0.7")

    assert {:taken, ^owner} = Runlocal.Registry.claim("claim-taken", self(), "10.0.0.8")
    assert Runlocal.Registry.lookup("claim-taken").channel_pid == owner

    Runlocal.Registry.unregister("claim-taken")
    Process.exit(owner, :kill)
  end

  test "claim does not take over when the client IP is unknown" do
    owner = spawn(fn -> Process.sleep(:infinity) end)
    Runlocal.Registry.register("claim-nil-ip", owner, nil)

    assert {:taken, ^owner} = Runlocal.Registry.claim("claim-nil-ip", self(), nil)

    Runlocal.Registry.unregister("claim-nil-ip")
    Process.exit(owner, :kill)
  end

  test "guarded unregister leaves a subdomain owned by someone else alone" do
    other = spawn(fn -> Process.sleep(:infinity) end)
    Runlocal.Registry.register("guarded", other, "10.0.0.1")

    assert Runlocal.Registry.unregister("guarded", self()) == 0
    assert Runlocal.Registry.lookup("guarded").channel_pid == other

    assert Runlocal.Registry.unregister("guarded", other) == 1
    assert Runlocal.Registry.lookup("guarded") == nil

    Process.exit(other, :kill)
  end

  test "count_by_ip returns 0 for unknown IP" do
    assert Runlocal.Registry.count_by_ip("10.0.0.99") == 0
  end

  test "count_by_ip returns 0 for nil" do
    assert Runlocal.Registry.count_by_ip(nil) == 0
  end

  test "count_by_ip counts entries with matching IP" do
    ip = "192.168.99.1"
    Runlocal.Registry.register("ip-count-1", self(), ip)
    Runlocal.Registry.register("ip-count-2", self(), ip)
    Runlocal.Registry.register("ip-count-3", self(), "10.0.0.1")

    assert Runlocal.Registry.count_by_ip(ip) == 2
    assert Runlocal.Registry.count_by_ip("10.0.0.1") == 1

    Runlocal.Registry.unregister("ip-count-1")
    Runlocal.Registry.unregister("ip-count-2")
    Runlocal.Registry.unregister("ip-count-3")
  end
end
