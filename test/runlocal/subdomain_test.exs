defmodule Runlocal.SubdomainTest do
  use ExUnit.Case, async: true

  test "generates adjective-animal format" do
    subdomain = Runlocal.Subdomain.generate()
    assert subdomain =~ ~r/^[a-z]+-[a-z]+$/
  end

  test "adjective is from the word list" do
    subdomain = Runlocal.Subdomain.generate()
    [adj, _animal] = String.split(subdomain, "-")
    assert adj in Runlocal.Subdomain.adjectives()
  end

  test "animal is from the word list" do
    subdomain = Runlocal.Subdomain.generate()
    [_adj, animal] = String.split(subdomain, "-")
    assert animal in Runlocal.Subdomain.animals()
  end

  test "generates unique subdomains in a batch" do
    subdomains = for _ <- 1..20, do: Runlocal.Subdomain.generate()
    assert length(Enum.uniq(subdomains)) == length(subdomains)
  end

  describe "pick_subdomain/3" do
    test "pro user with requested subdomain gets it" do
      assert Runlocal.Subdomain.pick_subdomain("acme", "pro", "my-api") == "my-api"
    end

    test "pro user without requested subdomain gets org_slug" do
      assert Runlocal.Subdomain.pick_subdomain("acme", "pro", nil) == "acme"
    end

    test "pro user with empty requested subdomain gets org_slug" do
      assert Runlocal.Subdomain.pick_subdomain("acme", "pro", "") == "acme"
    end

    test "free user with requested subdomain gets org_slug" do
      assert Runlocal.Subdomain.pick_subdomain("acme", "free", "my-api") == "acme"
    end

    test "free user without requested subdomain gets org_slug" do
      assert Runlocal.Subdomain.pick_subdomain("acme", "free", nil) == "acme"
    end

    test "pro user with invalid subdomain gets org_slug" do
      assert Runlocal.Subdomain.pick_subdomain("acme", "pro", "INVALID") == "acme"
      assert Runlocal.Subdomain.pick_subdomain("acme", "pro", "-start-dash") == "acme"
      assert Runlocal.Subdomain.pick_subdomain("acme", "pro", "ab") == "acme"
    end
  end

  describe "valid_subdomain?/1" do
    test "accepts valid subdomains" do
      assert Runlocal.Subdomain.valid_subdomain?("my-api")
      assert Runlocal.Subdomain.valid_subdomain?("abc")
      assert Runlocal.Subdomain.valid_subdomain?("test-123-app")
      assert Runlocal.Subdomain.valid_subdomain?("a0b")
    end

    test "rejects invalid subdomains" do
      refute Runlocal.Subdomain.valid_subdomain?("ab")
      refute Runlocal.Subdomain.valid_subdomain?("-start")
      refute Runlocal.Subdomain.valid_subdomain?("end-")
      refute Runlocal.Subdomain.valid_subdomain?("UPPER")
      refute Runlocal.Subdomain.valid_subdomain?("has space")
      refute Runlocal.Subdomain.valid_subdomain?("has.dot")
      refute Runlocal.Subdomain.valid_subdomain?(nil)
    end
  end
end
