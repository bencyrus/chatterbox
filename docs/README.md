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
