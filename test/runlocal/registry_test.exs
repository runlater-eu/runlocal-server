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
end
