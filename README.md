# Chatterbox

Internal overview. Business logic is in PostgreSQL; other services handle routing, token refresh, and file URL injection.

Architecture

- Caddy → Gateway → PostgREST → PostgreSQL
- Gateway → Files (only when a response includes a top-level `files` array)

Components

- caddy: public entrypoint, sets `X-Request-ID`, proxies to gateway. See [`caddy/Caddyfile`](caddy/Caddyfile).
- gateway: reverse proxy to PostgREST; best‑effort token refresh; injects processed file URLs. See [`gateway/internal`](gateway/internal).
- postgrest: HTTP API over PostgreSQL. Env in [`secrets/.env.postgrest`](secrets/.env.postgrest).
- files: resolves file IDs to URLs (placeholder). See [`files/cmd/files`](files/cmd/files) and [`files/internal/config`](files/internal/config).
- shared: common `logger` and `middleware`. See [`shared/logger`](shared/logger) and [`shared/middleware`](shared/middleware).
- datadog: log collection via compose labels.

Request flow

- Caddy assigns `X-Request-ID` and forwards.
- Gateway may refresh tokens (2s budget) then proxies to PostgREST.
- PostgREST executes DB logic/auth.
- Gateway injects `processed_files` when applicable.
- Response returns; new tokens (if any) are added to headers.

Orchestration

- [`docker-compose.yaml`](docker-compose.yaml) defines services and one bridge network. Only Caddy exposes 80/443.

Setup (dev)

- Create env files in [`secrets/`](secrets/) as per service READMEs.
- Start: `docker-compose up --build`.

References

- [`gateway/README.md`](gateway/README.md) — gateway responsibilities and env
- [`files/README.md`](files/README.md) — files service endpoints and behavior
- [`postgres/README.md`](postgres/README.md) — schema, roles, RPCs
- [`shared/README.md`](shared/README.md) — logging and middleware
- [`caddy/README.md`](caddy/README.md) — edge routing and headers
