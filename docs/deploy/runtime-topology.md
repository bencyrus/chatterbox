## Runtime Topology (Docker Compose)

Purpose

- Describe how services run together locally and in simple deployments: boundaries, ports, networks, and observability.

Services

- `caddy`: public entrypoint, exposes `80`/`443`, proxies all traffic to `gateway` on the internal network; adds/forwards `X-Request-ID`.
- `gateway`: reverse proxy to PostgREST; processes token refresh and file URL injection; internal only.
- `postgres`: database; exposes `5432` to host for dev; persists data volume; healthcheck using `pg_isready`.
- `postgrest`: HTTP API over Postgres; internal only; depends on healthy `postgres`.
- `files`: file URL helper service; exposes `9090` on host for dev.
- `worker`: background processor for `queues.task`; internal only; depends on `postgrest` start and healthy `postgres`.
- `datadog`: agent for log collection; tails container stdout based on labels.

Network

- Single bridge network `chattterbox-network` shared by all services (note the current triple‑t name in compose).

Observability

- Each service declares `com.datadoghq.ad.logs` labels with `source`/`service`; agent mounts Docker socket and tails stdout JSON logs.

Secrets and environment

- Service env files live under `secrets/`:
  - `.env.gateway`, `.env.worker`, `.env.files`, `.env.postgrest`, `.env.postgres`, `.env.datadog`.
- Migrations use placeholder substitution from `secrets/.env.postgres` via `postgres/scripts/apply_migrations.sh`:
  - Pattern `{secrets.<key>}` → env var: strip leading `secret_`, uppercase the rest.
  - Example: `{secrets.secret_jwt_secret}` → `JWT_SECRET`.
- Ensure JWT secret and PostgREST role config match values seeded by migrations.

Volumes

- `postgres_data` for DB state; `caddy_data`/`caddy_config` for Caddy state; `postgres/backups` mounted into container `/backups`.

Navigate

- Deploy: [`./README.md`](./README.md)
- Observability: [`../observability/README.md`](../observability/README.md)
- Caddy: [`../caddy/README.md`](../caddy/README.md)
- Shared: [`../shared/README.md`](../shared/README.md)
