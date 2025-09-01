Caddy

Purpose

- Public entrypoint. Terminates TLS, sets `X-Request-ID`, and proxies to the gateway.

Behavior

- Adds a UUID per request and forwards it upstream as `X-Request-ID`.
- Logs in JSON.

Configuration

- See [`caddy/Caddyfile`](Caddyfile) for domain and reverse proxy configuration.
- Certificates and config state are persisted via volumes in [`docker-compose.yaml`](../docker-compose.yaml).
