defmodule Runlocal.StatsTest do
  use ExUnit.Case

  test "track_tunnel increments counter" do
    before = Runlocal.Stats.summary()
    Runlocal.Stats.track_tunnel("1.2.3.4")
    after_stats = Runlocal.Stats.summary()
    assert after_stats.today.tunnels == before.today.tunnels + 1
  end

  test "track_request increments counter" do
    before = Runlocal.Stats.summary()
    Runlocal.Stats.track_request()
    after_stats = Runlocal.Stats.summary()
    assert after_stats.today.requests == before.today.requests + 1
  end

  test "unique IPs are counted" do
    before = Runlocal.Stats.summary()
    Runlocal.Stats.track_tunnel("10.20.30.40")
    Runlocal.Stats.track_tunnel("10.20.30.40")
    Runlocal.Stats.track_tunnel("10.20.30.41")
    after_stats = Runlocal.Stats.summary()
    assert after_stats.today.unique_ips >= before.today.unique_ips + 2
  end

  test "nil IP does not crash" do
    Runlocal.Stats.track_tunnel(nil)
  end

  test "summary includes active tunnels" do
    stats = Runlocal.Stats.summary()
    assert is_integer(stats.today.active_tunnels)
  end
end
