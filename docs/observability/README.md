## Observability and Logging

Status: current
Last verified: 2025-10-08

← Back to [`docs/README.md`](../README.md)

### Why this exists

- Provide consistent, structured logs across services with request correlation, and ship logs to Datadog using container labels.

### Role in the system

- Structured JSON logs via `shared/logger` across Go services (`gateway`, `files`, `worker`). Fields include:
  - `timestamp`, `level`, `service`, optional `request_id`, `message`, optional `error`, and context fields.
- Request correlation:
  - `caddy` generates `X-Request-ID` per request.
  - `shared/middleware.RequestIDMiddleware` propagates it into the request context and logs it on request start/end and subsequent logs in handlers.

### How it works

- `docker-compose.yaml` sets `com.datadoghq.ad.logs` labels on services (e.g., `gateway`, `postgrest`, `postgres`, `caddy`, `files`, `worker`). The Datadog agent container mounts Docker socket and reads these labels to tail stdout.
- Log formats:

- Go services (`gateway`, `files`, `worker`) emit JSON via `shared/logger`.
- `caddy` emits JSON (configured in `caddy/Caddyfile`).
- `postgres` and `postgrest` emit plain text by default; the agent still tails stdout under their `service` labels.

Source: [`docker-compose.yaml`](../../docker-compose.yaml)

```yaml
services:
  gateway:
    labels:
      - 'com.datadoghq.ad.logs=[{"source": "gateway", "service": "gateway"}]'
```

### Examples

- Gateway

  - Initializes logger with service name `gateway` and wraps the reverse proxy with `RequestIDMiddleware`.
  - Logs token refresh attempts/results and file URL injection steps. Response modifiers attach refreshed tokens to headers.

- Files service

  - Initializes logger as `files`, exposes `/healthz`, `/signed_download_url`, and `/signed_upload_url` endpoints.
  - Logs request id (if present), input size, and the number of processed file items.

- Worker
  - Initializes logger as `worker`; logs lifecycle, dequeues, and per-task processing.
  - Appends operational errors to `queues.error` via SQL for durable audit, in addition to logs.

### Operations

- Logs are the primary runtime signal; durable business/operational events are captured in Postgres (facts tables and `queues.error`).
- Correlation via `X-Request-ID` ties edge, gateway, and services together; background tasks have their own task‐centric logs with task ids.

### See also

- Docs index: [`../README.md`](../README.md)
- Shared components: [`../shared/README.md`](../shared/README.md)
- Caddy: [`../caddy/README.md`](../caddy/README.md)
- Runtime topology: [`../deploy/runtime-topology.md`](../deploy/runtime-topology.md)
- Deploy: [`../deploy/README.md`](../deploy/README.md)
- Backups/Restore: [`../deploy/backups-restore.md`](../deploy/backups-restore.md)
