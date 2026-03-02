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

### Subdomain modes

- **`random`** — Every tunnel gets a random subdomain like `swift-tiger`. Simple, no auth needed.
- **`custom`** — Clients can request a specific subdomain with `--subdomain myapp`. First-come-first-served, no API key required. Falls back to random if taken or not specified.
- **`runlater`** — Verifies API keys against runlater.eu. Used by the hosted runlocal.eu service.

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
