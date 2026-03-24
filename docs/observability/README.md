## Observability and Logging

Status: current
Last verified: 2026-03-24

← Back to [`docs/README.md`](../README.md)

### Why this exists

- Provide consistent, structured logs across all services with request correlation, and ship them to a centralized platform for querying and dashboards.
- Enable Postgres querying from the observability platform for business dashboards alongside operational logs.

### Role in the system

- All Go services (`gateway`, `files`, `worker`) emit structured JSON to stdout via [`shared/logger`](../shared/logger.md). Fields include `timestamp`, `level`, `service`, optional `request_id`, `message`, optional `error`, and context fields.
- `caddy` emits JSON access logs to stdout (configured in [`caddy/Caddyfile`](../../caddy/Caddyfile)).
- `postgres` and `postgrest` emit plain text to stdout.
- Request correlation: `caddy` generates `X-Request-ID` per request; [`shared/middleware.RequestIDMiddleware`](../shared/middleware.md) propagates it into context and logs.

### How it works

A sidecar container runs alongside the application stack, mounts the Docker socket, auto-discovers all containers, and tails their stdout/stderr. Logs are shipped to a centralized platform.

The current setup uses **Grafana Cloud** (Loki for logs, Postgres data source for database queries). The previous setup used Datadog.

- [Grafana Cloud setup](grafana-cloud.md) — current, active since 2026-03-24.
- [Datadog setup](datadog.md) — legacy, replaced by Grafana Cloud.

### Log formats

| Source | Format | Notes |
|--------|--------|-------|
| Go services (`gateway`, `files`, `worker`) | JSON | Via `shared/logger`; includes `request_id` when available |
| `caddy` | JSON | Configured in `Caddyfile` |
| `postgres`, `postgrest` | Plain text | Default output; still collected |
| `metabase`, `swaggerui`, `web` | Varies | Framework defaults |

### Operations

- Logs are the primary runtime signal; durable business and operational events are captured in Postgres (facts tables and `queues.error`).
- Correlation via `X-Request-ID` ties edge, gateway, and services together; background tasks have their own task-centric logs with task ids.
- Queue errors are written to `queues.error` by the worker in addition to being logged, providing a durable audit trail.

### See also

- Grafana Cloud setup: [`grafana-cloud.md`](grafana-cloud.md)
- Datadog setup (legacy): [`datadog.md`](datadog.md)
- Docs index: [`../README.md`](../README.md)
- Shared logger: [`../shared/logger.md`](../shared/logger.md)
- Shared middleware: [`../shared/middleware.md`](../shared/middleware.md)
- Caddy: [`../caddy/README.md`](../caddy/README.md)
- Runtime topology: [`../deploy/runtime-topology.md`](../deploy/runtime-topology.md)
- Deploy: [`../deploy/README.md`](../deploy/README.md)
