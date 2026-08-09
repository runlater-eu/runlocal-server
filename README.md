# runlocal

Expose localhost to the internet with one command.

```
npx runlocal 3000
```

**[runlocal.eu](https://runlocal.eu)** is the hosted version — no signup, no config, just works.

This repo is the open-source server. You can self-host it on your own domain.

## Quick start

### Docker

```bash
docker run -d \
  -p 4000:4000 \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e BASE_DOMAIN=tunnel.example.com \
  -e PHX_HOST=tunnel.example.com \
  -e PHX_SERVER=true \
  ghcr.io/runlater-eu/runlocal-server:latest
```

### From source

```bash
git clone https://github.com/runlater-eu/runlocal-server.git
cd runlocal
mix deps.get
mix assets.deploy
SECRET_KEY_BASE=$(mix phx.gen.secret) BASE_DOMAIN=tunnel.example.com PHX_HOST=tunnel.example.com PHX_SERVER=true MIX_ENV=prod mix phx.server
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_DOMAIN` | `runlocal.eu` | Your domain. Tunnels become `*.yourdomain.com` |
| `SECRET_KEY_BASE` | — | **Required in prod.** Generate with `mix phx.gen.secret` |
| `PHX_HOST` | `example.com` | Hostname for URL generation |
| `PORT` | `4000` | HTTP port |
| `PHX_SERVER` | — | Set to `true` to start the HTTP server |
| `SUBDOMAIN_MODE` | `random` | `random`, `custom`, or `runlater` (see below) |
| `LANDING_PAGE` | `false` | Set to `true` to show marketing pages (runlocal.eu only) |
| `RUNLATER_API_URL` | `https://runlater.eu` | Only needed for `runlater` subdomain mode |
| `BLOCKED_TUNNEL_ASNS` | — | Refuse anonymous tunnel creation from these networks, e.g. `57043,216246` (see below) |
| `BLOCKED_VISITOR_COUNTRIES` | — | Refuse tunnel visitors from these ISO country codes, e.g. `RU,KP` (see below) |
| `GEOIP_ASN_DB_URL` | DB-IP Lite | Override the ASN MMDB source (e.g. MaxMind GeoLite2 with your key) |
| `GEOIP_COUNTRY_DB_URL` | DB-IP Lite | Override the country MMDB source |

### Subdomain modes

- **`random`** — Every tunnel gets a random subdomain like `swift-tiger`. Simple, no auth needed.
- **`custom`** — Clients can request a specific subdomain with `--subdomain myapp`. First-come-first-served, no API key required. Falls back to random if taken or not specified.
- **`runlater`** — Verifies API keys against runlater.eu. Used by the hosted runlocal.eu service.

## Blocking abusive networks

Tunnel services attract abuse (phishing pages, scam apps), and the operators
typically connect from datacenter/hosting providers rather than residential
connections. Two optional, independent blocklists help with this — both are
**off by default**:

- **`BLOCKED_TUNNEL_ASNS`** blocks tunnel *creation* by autonomous system.
  List the AS numbers of hosting providers you've seen abuse from. Only
  anonymous clients are blocked; in `runlater` mode a verified API key
  bypasses the list, so legitimate datacenter users have a path in.
- **`BLOCKED_VISITOR_COUNTRIES`** blocks tunnel *visitors* by country
  (ISO 3166-1 alpha-2 codes). Useful when abusive content targets audiences
  in specific regions. Applies only to `*.yourdomain` tunnel traffic, never
  to the base domain or to tunnel clients.

When either list is set, the matching IP database is downloaded at startup
and refreshed automatically. Lookups fail open: if the database isn't
available or an IP can't be resolved, nothing is blocked.

By default this uses the free [DB-IP Lite](https://db-ip.com/db/lite.php)
databases (IP geolocation by [DB-IP](https://db-ip.com), licensed
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)) — no account or
license key needed. The monthly download URL is pinned at boot; restarts pick
up the newest release. To use MaxMind GeoLite2 instead, point
`GEOIP_ASN_DB_URL` / `GEOIP_COUNTRY_DB_URL` at your keyed GeoLite2 URLs.

## DNS setup

Point a wildcard DNS record at your server:

```
*.tunnel.example.com  A  → your-server-ip
tunnel.example.com    A  → your-server-ip
```

## TLS

runlocal speaks plain HTTP. Put a reverse proxy in front for TLS:

**Caddy** (automatic HTTPS):
```
*.tunnel.example.com, tunnel.example.com {
    reverse_proxy localhost:4000
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
}
```

**nginx** + certbot, Traefik, or any other reverse proxy works too.

## Connecting the CLI

```bash
npx runlocal 3000 --server wss://tunnel.example.com
```

Or set the environment variable:

```bash
export RUNLOCAL_HOST=wss://tunnel.example.com
npx runlocal 3000
```

## License

MIT — see [LICENSE](LICENSE).

Built by [Whitenoise AS](https://runlater.eu) (Oslo, Norway).
