## Postgres Architecture

Status: current
Last verified: 2025-10-08

← Back to [`docs/README.md`](../README.md)

### Why this exists

- Document the database‑centric design: schemas, roles, public API via PostgREST, and where to find domain docs.

### Role in the system

- Source of truth for logic, auth, and data. PostgREST exposes the HTTP API from DB schemas and functions.
- Supervisors orchestrate workflows; the worker executes tasks with minimal privileges.

### Schemas (by purpose)

- `api`: public schema that exposes database objects by PostgREST. Functions are accessible at `/rpc/*` endpoints and views are at `/*`.
- `accounts`: account data model and helpers (email/phone normalization, signup support, etc.).
- `auth`: JWT token creation/verification, refresh flow, login-with-code tables/functions, etc.
- `queues`: generic task queue tables and functions (enqueue/dequeue, error log, etc.).
- `internal`: configuration key-value store and the `internal.run_function(name, payload)` runner.
- `comms`: communications (email/sms) data, templates, comms supervisors, and handlers.

### Roles

- `anon`, `authenticated`: application roles assumed by PostgREST.
- `authenticator`: PostgREST connection role (switches into `anon`/`authenticated`).
- `worker_service_user`: dedicated worker role with minimal grants.

### Public API

- PostgREST serves views and `api.*` functions.
- Notable RPCs include:
  - `api.signup(password, email, phone_number)`
  - `api.login(identifier, password)`
  - `api.refresh_tokens(refresh_token)`
  - `api.request_login_code(identifier)`
  - `api.login_with_code(identifier, code)`
  - Hello world examples: `api.hello_world_email(to_address)`, `api.hello_world_sms(to_number)`
- Notable views include:
  - `api.hello_world`
  - `api.hello_secure`

### Configuration and secrets

- Environment variables used by the Postgres service and migrations:
  - `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `PGTZ` (container timezone)
  - `AUTHENTICATOR_PASSWORD` (used by migrations to set the `authenticator` role password)
  - `JWT_SECRET` (seeded into `internal.config('jwt')`)
  - `HELLO_EMAIL`, `NOREPLY_EMAIL` (seeded into `internal.config('from_emails')`)
- Sources:
  - Compose: [`docker-compose.yaml`](../../docker-compose.yaml)
  - Migrations seeding config: [`postgres/migrations/1756072325_config_setup.sql`](../../postgres/migrations/1756072325_config_setup.sql)

### See also

- Basics first:
  - [SQL Style Guide](sql-style-guide.md)
  - [Queues and Worker](queues-and-worker.md)
  - [Comms](comms.md)
  - [OTP Login](otp-login.md)
  - [Migrations and Secrets](migrations-and-secrets.md)
- Security/grants:
  - See: [Security and Grants](security.md)
