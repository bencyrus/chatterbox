## Chatterbox Documentation

Status: current
Last verified: 2025-10-08

### Why this exists

- Provide a single, accurate entry point to the architecture and how to work within it.
- Keep links to deeper subsystem docs and style guides in one place.

### Role in the system

- Documentation overview for engineers building and operating Chatterbox.
- Defines how subsystems fit together and where to learn more.

### How it works

- Postgres‑first application: public API and business logic live in the database, exposed via PostgREST.
- Go services (gateway, worker, files) are thin and delegate business logic to SQL functions and supervisors.
- Workflows are orchestrated as supervisor‑driven processes: append‑only facts derive state; supervisors enqueue child tasks and may re‑enqueue themselves; the worker executes tasks.

### Documentation map

- Concepts: [Core architectural ideas](concepts/README.md)

  - Why the Supervisor Pattern: [Supervisors rationale](concepts/why-supervisor.md)

- Postgres Architecture: [Database-first design](postgres/README.md)

  - SQL Style Guide: [Conventions for migrations/functions](postgres/sql-style-guide.md)
  - Security and Grants: [Roles and privileges](postgres/security.md)
  - Queues and Worker: [DB queue and worker contract](postgres/queues-and-worker.md)
  - Communications (email and SMS): [Data model, supervisors, handlers](postgres/comms.md)
  - OTP Login (passwordless): [Flow and helpers](postgres/otp-login.md)
  - Migrations and Secrets: [Applying migrations and env mapping](postgres/migrations-and-secrets.md)

- Gateway: [Reverse proxy and edge logic](gateway/README.md)

  - Gateway Auth Refresh: [Opportunistic token refresh](gateway/auth-refresh.md)
  - Gateway File URL Injection: [Response enrichment for files](gateway/files-injection.md)

- Worker: [Background task processor](worker/README.md)

  - Worker Lifecycle: [Dequeue, dispatch, process](worker/lifecycle.md)
  - Worker Task Payloads and Handlers: [Shapes and envelope](worker/payloads.md)
  - Worker Email Processor: [Resend integration](worker/email.md)
  - Worker SMS Processor: [Simulated provider](worker/sms.md)

- Files Service: [Signed URL helper](files/README.md)

- Caddy (Reverse Proxy): [Public entrypoint and correlation](caddy/README.md)

- Shared Components: [Common libraries](shared/README.md)

  - Shared Logger: [JSON logging API](shared/logger.md)
  - Shared HTTP Middleware: [Request ID and access logs](shared/middleware.md)

- Observability and Logging: [Datadog and correlation](observability/README.md)

- Deploy and Operations: [Overview](deploy/README.md)

  - Runtime Topology (Docker Compose): [Services, ports, network](deploy/runtime-topology.md)
  - Backups and Restore: [Scripts and procedures](deploy/backups-restore.md)

### Start here

- Concepts: [`docs/concepts/README.md`](concepts/README.md)
- Postgres: [`docs/postgres/README.md`](postgres/README.md)
- Gateway: [`docs/gateway/README.md`](gateway/README.md)
- Worker: [`docs/worker/README.md`](worker/README.md)
- Files: [`docs/files/README.md`](files/README.md)
- Caddy (reverse proxy): [`docs/caddy/README.md`](caddy/README.md)

### Operations

- Runtime topology: [`docs/deploy/runtime-topology.md`](deploy/runtime-topology.md)
- Backups & restore: [`docs/deploy/backups-restore.md`](deploy/backups-restore.md)

### See also

- SQL style guide: [`docs/postgres/sql-style-guide.md`](postgres/sql-style-guide.md)
- Worker lifecycle: [`docs/worker/lifecycle.md`](worker/lifecycle.md)
- Worker payloads: [`docs/worker/payloads.md`](worker/payloads.md)
