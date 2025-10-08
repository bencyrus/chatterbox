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

- Concepts

  - Overview: [concepts/README.md](concepts/README.md)
  - Why the Supervisor Pattern: [concepts/why-supervisor.md](concepts/why-supervisor.md)

- Postgres

  - Overview: [postgres/README.md](postgres/README.md)
  - SQL Style Guide: [postgres/sql-style-guide.md](postgres/sql-style-guide.md)
  - Security and Grants: [postgres/security.md](postgres/security.md)
  - Queues and Worker: [postgres/queues-and-worker.md](postgres/queues-and-worker.md)
  - Communications (email and SMS): [postgres/comms.md](postgres/comms.md)
  - OTP Login (passwordless): [postgres/otp-login.md](postgres/otp-login.md)
  - Migrations and Secrets: [postgres/migrations-and-secrets.md](postgres/migrations-and-secrets.md)

- Gateway

  - Overview: [gateway/README.md](gateway/README.md)
  - Auth Refresh: [gateway/auth-refresh.md](gateway/auth-refresh.md)
  - File URL Injection: [gateway/files-injection.md](gateway/files-injection.md)

- Worker

  - Overview: [worker/README.md](worker/README.md)
  - Lifecycle: [worker/lifecycle.md](worker/lifecycle.md)
  - Payloads: [worker/payloads.md](worker/payloads.md)
  - Email: [worker/email.md](worker/email.md)
  - SMS: [worker/sms.md](worker/sms.md)

- Files

  - Overview: [files/README.md](files/README.md)

- Caddy

  - Overview: [caddy/README.md](caddy/README.md)

- Shared

  - Overview: [shared/README.md](shared/README.md)
  - Logger: [shared/logger.md](shared/logger.md)
  - HTTP Middleware: [shared/middleware.md](shared/middleware.md)

- Observability

  - Overview: [observability/README.md](observability/README.md)

- Deploy
  - Overview: [deploy/README.md](deploy/README.md)
  - Runtime Topology: [deploy/runtime-topology.md](deploy/runtime-topology.md)
  - Backups and Restore: [deploy/backups-restore.md](deploy/backups-restore.md)

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
