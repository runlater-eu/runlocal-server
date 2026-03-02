defmodule Runlocal.RegistryTest do
  use ExUnit.Case, async: true

  test "register and lookup" do
    token = Runlocal.Registry.register("test-sub", self())
    assert is_binary(token) and byte_size(token) > 0
    result = Runlocal.Registry.lookup("test-sub")
    assert result.channel_pid == self()
    assert result.inspect_token == token
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
