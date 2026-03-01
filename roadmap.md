# Roadmap

## ~~Abuse prevention~~ (done)
- ~~**WebSocket message size limit** — `max_frame_size: 11_000_000` in endpoint.ex~~
- ~~**IP blocklist** — ETS-backed `Runlocal.IpBlocklist` module, checked at socket connect + HTTP proxy~~
- ~~**Bandwidth cap per tunnel** — `Runlocal.BandwidthLimiter` tracks bytes/sec per subdomain (50MB/s window)~~

## Auth & access control
- **API key for tunnel creation** — move from anonymous to authenticated, lets you enforce per-user limits and revoke access
- **Custom subdomains** — let authenticated users reserve a name like `myapp.runlocal.eu`

## Observability
- **Structured logging / metrics** — track tunnels created, requests proxied, rate limit hits, error rates via Phoenix Telemetry
- **Admin dashboard** — see active tunnels, top IPs, abuse patterns

## Reliability
- **Horizontal scaling** — the ETS registry is single-node; moving to distributed Erlang or Redis would let you run multiple instances
- **Graceful reconnection** — if the WebSocket drops, let the CLI reclaim the same subdomain within a grace period
- **Request queuing** — if the tunnel client is slow, queue a few requests instead of immediately timing out

## Polish
- **HTTPS-only redirect** — ensure HTTP requests redirect to HTTPS
- **Proper error pages** — return HTML for browser requests, plain text for API
- **Compression** — gzip proxy responses for bandwidth savings
