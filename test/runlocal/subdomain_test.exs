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
end
