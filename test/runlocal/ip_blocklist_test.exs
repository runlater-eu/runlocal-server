defmodule Runlocal.IpBlocklistTest do
  use ExUnit.Case, async: true

  test "unknown IP is not blocked" do
    refute Runlocal.IpBlocklist.blocked?("10.0.0.1")
  end

  test "nil IP is not blocked" do
    refute Runlocal.IpBlocklist.blocked?(nil)
  end

  test "block and check" do
    Runlocal.IpBlocklist.block("192.168.50.1")
    assert Runlocal.IpBlocklist.blocked?("192.168.50.1")
    Runlocal.IpBlocklist.unblock("192.168.50.1")
  end

  test "unblock removes IP" do
    Runlocal.IpBlocklist.block("192.168.50.2")
    assert Runlocal.IpBlocklist.blocked?("192.168.50.2")
    Runlocal.IpBlocklist.unblock("192.168.50.2")
    refute Runlocal.IpBlocklist.blocked?("192.168.50.2")
  end

  test "list returns blocked IPs" do
    Runlocal.IpBlocklist.block("192.168.50.3")
    entries = Runlocal.IpBlocklist.list()
    assert Enum.any?(entries, fn %{ip: ip} -> ip == "192.168.50.3" end)
    Runlocal.IpBlocklist.unblock("192.168.50.3")
  end
end
