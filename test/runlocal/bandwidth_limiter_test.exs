defmodule Runlocal.BandwidthLimiterTest do
  use ExUnit.Case, async: true

  test "allows small request" do
    assert Runlocal.BandwidthLimiter.allow?("bw-test-1", 1000)
    Runlocal.BandwidthLimiter.cleanup("bw-test-1")
  end

  test "allows up to 50MB in one window" do
    assert Runlocal.BandwidthLimiter.allow?("bw-test-2", 25_000_000)
    assert Runlocal.BandwidthLimiter.allow?("bw-test-2", 25_000_000)
    Runlocal.BandwidthLimiter.cleanup("bw-test-2")
  end

  test "denies when bandwidth exceeded" do
    assert Runlocal.BandwidthLimiter.allow?("bw-test-3", 50_000_000)
    refute Runlocal.BandwidthLimiter.allow?("bw-test-3", 1)
    Runlocal.BandwidthLimiter.cleanup("bw-test-3")
  end

  test "resets after window expires" do
    assert Runlocal.BandwidthLimiter.allow?("bw-test-4", 50_000_000)
    refute Runlocal.BandwidthLimiter.allow?("bw-test-4", 1)
    Process.sleep(1100)
    assert Runlocal.BandwidthLimiter.allow?("bw-test-4", 1000)
    Runlocal.BandwidthLimiter.cleanup("bw-test-4")
  end

  test "cleanup resets tracking" do
    Runlocal.BandwidthLimiter.allow?("bw-test-5", 50_000_000)
    Runlocal.BandwidthLimiter.cleanup("bw-test-5")
    assert Runlocal.BandwidthLimiter.allow?("bw-test-5", 50_000_000)
    Runlocal.BandwidthLimiter.cleanup("bw-test-5")
  end
end
