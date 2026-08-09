defmodule Runlocal.GeoIPTest do
  use ExUnit.Case, async: true

  # config/test.exs pins the :geoip_static entries and blocklists used here.

  test "blocked_asn?/1 matches configured ASNs" do
    assert Runlocal.GeoIP.blocked_asn?("198.51.100.10")
    refute Runlocal.GeoIP.blocked_asn?("198.51.100.20")
  end

  test "blocked_country?/1 matches configured countries" do
    assert Runlocal.GeoIP.blocked_country?("198.51.100.10")
    refute Runlocal.GeoIP.blocked_country?("198.51.100.20")
  end

  test "unresolvable IPs fail open" do
    refute Runlocal.GeoIP.blocked_asn?("203.0.113.99")
    refute Runlocal.GeoIP.blocked_country?("203.0.113.99")
  end

  test "nil IP fails open" do
    refute Runlocal.GeoIP.blocked_asn?(nil)
    refute Runlocal.GeoIP.blocked_country?(nil)
  end
end
