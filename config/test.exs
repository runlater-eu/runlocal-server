import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :runlocal, RunlocalWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "bAJLtnmP9ycVcLnZQLZXHsFFRprwZqzW/0VCpQrwvaG0NmziTetCCYNrEql5bayM",
  server: false

config :runlocal, base_domain: "localhost"
config :runlocal, subdomain_mode: :random
config :runlocal, landing_page: false

# GeoIP lookups are stubbed in tests: :geoip_static replaces the MMDB
# databases entirely, so nothing is ever downloaded (documentation-range IPs).
config :runlocal,
  blocked_tunnel_asns: [64500],
  blocked_visitor_countries: ["XZ"],
  geoip_static: %{
    "198.51.100.10" => %{asn: 64500, country: "XZ"},
    "198.51.100.20" => %{asn: 64501, country: "DE"}
  }

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
