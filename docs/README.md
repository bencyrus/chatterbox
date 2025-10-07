## Chatterbox Documentation

Purpose

- A single entry point to understand Chatterbox’s architecture and how to build within it.
- Links to deeper Postgres documentation and style guidance.

What this system is

- Postgres-first application: logic and public API live in the database (exposed via PostgREST). Go services are thin (gateway, worker, files) and defer business logic to SQL functions.
- Workflows are orchestrated as supervisor-driven processes: append-only facts derive state; supervisors enqueue child tasks and may re-enqueue themselves; the worker only executes.

Start here

- Concepts: [docs/concepts/README.md](concepts/README.md)
- Postgres: [docs/postgres/README.md](postgres/README.md)
- Gateway: [docs/gateway/README.md](gateway/README.md)
- Worker: [docs/worker/README.md](worker/README.md)
- Files: [docs/files/README.md](files/README.md)

Notes on navigation

- Each area has its own README with its own recommended reading order.
