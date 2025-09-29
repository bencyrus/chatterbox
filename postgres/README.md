PostgreSQL

Purpose

- Source of truth for logic, auth, and data. PostgREST exposes the HTTP API from DB schemas and functions.

Schemas and roles

- Schemas: `api` (exposed), `auth` (authn/z), `internal` (config/utility).
- Roles: `anon`, `authenticated`, `authenticator` (connection role for PostgREST).

Auth model

- Accounts and tokens live under `auth.*`.
- Access/refresh token model; refresh exchanged via RPC.
- Row‑level security where applicable.

RPC

- Public endpoints are implemented as functions in `api.*` (become `/rpc/*`).
- Token refresh RPC referenced by gateway: see definition in `1756072325_basic_auth.sql`.

Migrations

- SQL files in this folder are applied in order. See `1756072100_setup.sql` then `1756072325_basic_auth.sql`.

Configuration

- PostgREST env file: [`secrets/.env.postgrest`](../secrets/.env.postgrest).
- JWT secret must match gateway.

References

- Base setup: [`1756072100_setup.sql`](1756072100_setup.sql)
- Auth and RPCs: [`1756072325_basic_auth.sql`](1756072325_basic_auth.sql)
- Queues and worker base: [`1756074000_base_queues_and_worker.sql`](1756074000_base_queues_and_worker.sql)
- Comms schema, supervisors, handlers, and API: [`1756074200_comms_queue.sql`](1756074200_comms_queue.sql)
