# Database Patterns

These patterns form the toolkit of a database-first system. Each is battle-tested, composable, and designed to push complexity into the database where it can be enforced uniformly — regardless of which service, language, or framework sits above it.

---

## Schema Organization

Use schemas as module boundaries. Each schema owns a domain:

| Schema | Purpose |
|--------|---------|
| `accounts` | Users, organizations, memberships |
| `auth` | Sessions, tokens, credentials |
| `comms` | Email tasks, SMS tasks, notifications |
| `queues` | Generic task queue infrastructure |
| `files` | Upload metadata, storage references |
| `api` | PostgREST-exposed interface |
| `internal` | Shared utilities, trigger functions |

The `api` schema is special — it's the only schema exposed to PostgREST. Everything else is an internal implementation detail, accessible only through functions granted to specific roles.

```sql
create schema accounts;
create schema auth;
create schema comms;
create schema queues;
create schema files;
create schema api;
create schema internal;

comment on schema api is 'Public-facing API layer. Exposed via PostgREST.';
comment on schema internal is 'Shared utilities. Never exposed externally.';
```

This gives you the benefits of a microservice architecture (bounded contexts, clear ownership) without the operational cost of network boundaries.

---

## ID Generation

Use `bigserial` for internal primary keys. They're fast, compact, and produce excellent B-tree locality:

```sql
create table accounts.account (
  account_id bigserial primary key,
  display_name text not null
);
```

For external-facing identifiers where enumeration prevention matters, use opaque IDs. UUID v7 is time-ordered and B-tree friendly (native support arrives in PostgreSQL 18):

```sql
create table files.upload (
  upload_id bigserial primary key,
  external_id uuid not null default gen_random_uuid(),
  -- ...
  constraint uq_upload_external_id unique (external_id)
);
```

**When to use which:**
- `bigserial` — internal references, foreign keys, join columns
- UUID v7 / CUID2 — URLs, API responses, anything a user or third party can see

---

## Audit Trail Pattern

Every table gets `created_at` and `updated_at`. A shared trigger function maintains `updated_at` automatically:

```sql
create or replace function internal.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table accounts.account (
  account_id bigserial primary key,
  display_name text not null,
  email accounts.email not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_updated_at
  before update on accounts.account
  for each row execute function internal.set_updated_at();
```

For sensitive operations, extend the pattern with actor tracking:

```sql
alter table accounts.account
  add column created_by bigint references accounts.account(account_id),
  add column updated_by bigint references accounts.account(account_id);
```

**Why it matters:** Every row tells you when it was born and when it last changed. No application code required — the database enforces it.

---

## Soft Delete Pattern

Use a boolean flag or `deleted_at` timestamp. Pair it with a partial index so queries on active records stay fast:

```sql
alter table accounts.account
  add column is_deleted boolean not null default false;

create index idx_account_active
  on accounts.account (account_id)
  where not is_deleted;
```

API functions filter by default:

```sql
create or replace function api.get_account(_account_id bigint)
returns accounts.account language plpgsql stable as $$
declare _account accounts.account;
begin
  select * into _account
  from accounts.account
  where account_id = _account_id
    and not is_deleted;

  if not found then
    raise exception 'Account not found'
      using errcode = 'P0002';
  end if;

  return _account;
end;
$$;
```

**When to use:** Any entity that users or admins may need to recover, or where referential integrity prevents hard deletion. The partial index means active-record queries never scan deleted rows.

---

## Append-Only State

Never UPDATE business state. Append facts instead, and derive current state from the trail:

```sql
-- BAD: mutable status column
update orders.order set status = 'shipped' where order_id = 123;

-- GOOD: append a fact
insert into orders.order_event (order_id, event_type, occurred_at)
values (123, 'shipped', now());
```

Derive current state from facts:

```sql
create or replace function orders.current_status(_order_id bigint)
returns text language sql stable as $$
  select event_type
  from orders.order_event
  where order_id = _order_id
  order by occurred_at desc
  limit 1;
$$;
```

Or use a materialized view for hot-path reads:

```sql
create materialized view orders.order_current_status as
select distinct on (order_id)
  order_id,
  event_type as current_status,
  occurred_at as status_since
from orders.order_event
order by order_id, occurred_at desc;
```

**Why it matters:** You get a full audit trail for free. State is debuggable — you can replay the history. Idempotency comes naturally (inserting the same fact twice is a constraint violation, not silent corruption).

---

## Domain Types

Use domains with CHECK constraints instead of raw enums. They're easier to extend (no `ALTER TYPE ... ADD VALUE` inside transactions) and self-documenting:

```sql
create domain accounts.email as text
  check (value ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

create domain accounts.phone_number as text
  check (value ~ '^\+[1-9]\d{1,14}$');

create domain queues.task_type as text
  check (value in (
    'db_function',
    'email',
    'sms',
    'file_delete',
    'transcription_kickoff'
  ));
```

**When to use:** Any column that represents a constrained text value. Domains carry their validation wherever they're used — you define the rule once, and every table that uses `accounts.email` inherits it.

---

## Transactional Outbox Pattern

Business data and the corresponding job must be created in the same transaction. If the transaction rolls back, both disappear:

```sql
create or replace function api.send_welcome_email(_account_id bigint)
returns void language plpgsql as $$
begin
  insert into comms.send_email_task (account_id, template_key)
  values (_account_id, 'welcome');

  perform queues.enqueue('db_function', jsonb_build_object(
    'db_function', 'comms.send_email_supervisor',
    'send_email_task_id', currval('comms.send_email_task_send_email_task_id_seq')
  ));
end;
$$;
```

**Why it matters:** No two-phase commit. No phantom jobs from rolled-back transactions. No lost jobs from committed transactions that failed to enqueue. The database transaction is the coordination mechanism.

---

## Lease-Based Queue

Use `FOR UPDATE SKIP LOCKED` for a high-concurrency, zero-contention work queue:

```sql
create or replace function queues.dequeue_next_available_task()
returns queues.task language plpgsql as $$
declare _task queues.task;
begin
  select t.* into _task
  from queues.task t
  where not exists (
    select 1 from queues.task_completed c
    where c.task_id = t.task_id
  )
  and not exists (
    select 1 from queues.task_lease l
    where l.task_id = t.task_id
      and l.expires_at > now()
  )
  and t.scheduled_at <= now()
  order by t.scheduled_at, t.task_id
  limit 1
  for update skip locked;

  if _task.task_id is null then
    return null;
  end if;

  insert into queues.task_lease (task_id, expires_at)
  values (_task.task_id, now() + interval '5 minutes');

  return _task;
end;
$$;
```

**How it works:**
- `SKIP LOCKED` means concurrent workers never block each other — they skip rows already being processed
- Lease records are append-only, giving you a debugging audit trail of every attempt
- If a worker crashes, the lease expires and the task becomes available to the next worker
- No external queue infrastructure required

---

## Security: Role-Based Grants

Each service gets its own database user with minimal privileges. Grant access to functions, not tables:

```sql
create user web_api_user with login password '{secrets.web_api_user_password}';
create user worker_service_user with login password '{secrets.worker_service_user_password}';

-- Web API can call API-layer functions
grant usage on schema api to web_api_user;
grant execute on all functions in schema api to web_api_user;

-- Worker can only dequeue and complete tasks
grant usage on schema queues to worker_service_user;
grant execute on function queues.dequeue_next_available_task() to worker_service_user;
grant execute on function queues.complete_task(bigint) to worker_service_user;
```

Business functions use `SECURITY DEFINER` to escalate privileges within the function body:

```sql
create or replace function api.create_account(_display_name text, _email text)
returns bigint language plpgsql security definer as $$
declare _account_id bigint;
begin
  insert into accounts.account (display_name, email)
  values (_display_name, _email)
  returning account_id into _account_id;

  return _account_id;
end;
$$;
```

**Why it matters:** Even if an attacker gains access to a service's credentials, they can only call the functions granted to that role — never raw table access. The attack surface is the function signature, not the entire schema.

---

## JSONB for Flexible Payloads

Use typed columns for things you query. Use JSONB for things you pass through:

```sql
create table queues.task (
  task_id bigserial primary key,
  task_type queues.task_type not null,
  payload jsonb not null default '{}',
  scheduled_at timestamptz not null default now()
);

create index idx_task_payload_function
  on queues.task ((payload->>'db_function'))
  where task_type = 'db_function';
```

For webhook payloads where you need byte-exact signature verification, store the raw body as `text`:

```sql
create table comms.inbound_webhook (
  inbound_webhook_id bigserial primary key,
  provider text not null,
  raw_body text not null,
  headers jsonb not null,
  received_at timestamptz not null default now()
);
```

**When to use JSONB vs. text:**
- JSONB — structured payloads you may index or query into
- text — raw payloads where byte-exact preservation matters (signature verification, legal records)

---

## Constraint Patterns

### Uniqueness for Idempotency

Prevent duplicate processing with unique constraints:

```sql
create table queues.task_completed (
  task_completed_id bigserial primary key,
  task_id bigint not null references queues.task(task_id),
  completed_at timestamptz not null default now(),
  constraint uq_task_completed_task_id unique (task_id)
);
```

Inserting a duplicate is a constraint violation, not silent corruption.

### Partial Unique Indexes

Enforce uniqueness only within a subset of rows:

```sql
create unique index uq_account_email_active
  on accounts.account (email)
  where not is_deleted;
```

This allows a deleted account's email to be reused by a new account.

### CHECK Constraints for Business Rules

```sql
alter table orders.order_event
  add constraint chk_event_type
  check (event_type in ('created', 'confirmed', 'shipped', 'delivered', 'cancelled'));

alter table files.upload
  add constraint chk_file_size
  check (file_size_bytes > 0 and file_size_bytes <= 104857600);
```

### Foreign Keys with Cascading

Use cascading deletes sparingly and intentionally:

```sql
create table auth.session (
  session_id bigserial primary key,
  account_id bigint not null references accounts.account(account_id) on delete cascade,
  expires_at timestamptz not null
);
```

**Rule of thumb:** Cascade only for true ownership relationships (account → sessions). For associative relationships, use `on delete restrict` and handle deletion explicitly.

---

## Secret Substitution in Migrations

Never hardcode secrets in migration files. Use placeholder tokens that a deployment script substitutes from environment variables:

```sql
-- In migration file: 003_create_service_users.sql
create user worker_service_user with login password '{secrets.worker_service_user_password}';
create user web_api_user with login password '{secrets.web_api_user_password}';
```

The deployment script performs substitution at apply time:

```bash
#!/usr/bin/env bash
set -euo pipefail

for file in migrations/*.sql; do
  sed \
    -e "s|{secrets.worker_service_user_password}|${WORKER_SERVICE_USER_PASSWORD}|g" \
    -e "s|{secrets.web_api_user_password}|${WEB_API_USER_PASSWORD}|g" \
    "$file" | psql "$DATABASE_URL"
done
```

**Why it matters:** Migration files can be committed to version control without exposing credentials. Secrets live in your deployment environment (Vault, AWS Secrets Manager, CI variables) and are injected at runtime.

---

## Composing Patterns

These patterns are designed to work together. A typical operation combines several:

```sql
create or replace function api.place_order(_account_id bigint, _items jsonb)
returns bigint language plpgsql security definer as $$
declare _order_id bigint;
begin
  -- Insert with audit columns (Audit Trail Pattern)
  insert into orders.order (account_id, created_by)
  values (_account_id, _account_id)
  returning order_id into _order_id;

  -- Append initial state (Append-Only Pattern)
  insert into orders.order_event (order_id, event_type)
  values (_order_id, 'created');

  -- Enqueue fulfillment (Transactional Outbox Pattern)
  perform queues.enqueue('db_function', jsonb_build_object(
    'db_function', 'orders.begin_fulfillment',
    'order_id', _order_id
  ));

  return _order_id;
end;
$$;
```

One function, one transaction, multiple patterns — all enforced by the database regardless of what calls it.
