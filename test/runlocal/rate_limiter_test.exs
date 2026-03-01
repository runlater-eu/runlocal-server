defmodule Runlocal.RateLimiterTest do
  use ExUnit.Case, async: true

  test "allows requests within limit" do
    assert Runlocal.RateLimiter.allow?("rl-test-1")
    Runlocal.RateLimiter.cleanup("rl-test-1")
  end

  test "allows up to 10 requests" do
    for _ <- 1..10 do
      assert Runlocal.RateLimiter.allow?("rl-test-2")
    end

    Runlocal.RateLimiter.cleanup("rl-test-2")
  end

  test "denies after 10 requests" do
    for _ <- 1..10 do
      Runlocal.RateLimiter.allow?("rl-test-3")
    end

    refute Runlocal.RateLimiter.allow?("rl-test-3")
    Runlocal.RateLimiter.cleanup("rl-test-3")
  end

  test "cleanup removes entry" do
    Runlocal.RateLimiter.allow?("rl-test-4")
    Runlocal.RateLimiter.cleanup("rl-test-4")

    # After cleanup, should get a fresh bucket
    assert Runlocal.RateLimiter.allow?("rl-test-4")
    Runlocal.RateLimiter.cleanup("rl-test-4")
  end
end
