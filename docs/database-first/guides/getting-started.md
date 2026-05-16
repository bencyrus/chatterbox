# Getting Started

This guide walks you through setting up a database-first system from scratch. By the end, you'll have a working API powered entirely by PostgreSQL — no application server code required.

## Prerequisites

- Docker and Docker Compose installed
- Basic PostgreSQL knowledge (CREATE TABLE, SELECT, functions)
- A terminal

## Step 1: The Minimum Viable Stack

A database-first system needs three components:

1. **PostgreSQL** — holds your application logic, not just your data
2. **PostgREST** — automatically generates a REST API from your database schema
3. **A reverse proxy** (Caddy recommended) — handles TLS, routing, and request correlation

Create a `docker-compose.yaml`:

```yaml
services:
  postgres:
    image: postgres:18-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_PASSWORD: secret
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/01-init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d myapp"]
      interval: 5s
      timeout: 5s
      retries: 20

  postgrest:
    image: postgrest/postgrest:latest
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      PGRST_DB_URI: postgres://authenticator:authpass@postgres:5432/myapp
      PGRST_DB_ANON_ROLE: anon
      PGRST_DB_SCHEMA: api
    ports:
      - "3000:3000"
```

Start it up:

```bash
docker compose up -d
```

PostgreSQL starts first. PostgREST waits for the healthcheck to pass, then connects and introspects your schema to build the API.

## Step 2: Set Up Your Database Roles

Create a file called `init.sql`. This runs automatically when the container first starts.

```sql
-- The authenticator role (PostgREST connects as this user)
create role authenticator noinherit login password 'authpass';

-- Anonymous role (unauthenticated requests)
create role anon nologin;
grant anon to authenticator;

-- Authenticated role (JWT-bearing requests)
create role authenticated nologin;
grant authenticated to authenticator;
```

This is the security foundation. PostgREST connects as `authenticator`, then switches to `anon` or `authenticated` based on the incoming request's JWT. PostgreSQL's role system enforces all access control — no middleware required.

## Step 3: Create Your API Schema

Add this to your `init.sql` below the roles:

```sql
-- The api schema is what PostgREST exposes to the world
create schema if not exists api;

-- Grant schema access to both roles
grant usage on schema api to anon, authenticated;

-- Your first endpoint: a simple RPC function
create or replace function api.hello()
returns json
language sql
stable
as $$
  select json_build_object('message', 'Hello from the database!');
$$;

grant execute on function api.hello() to anon;
```

Rebuild and test:

```bash
docker compose down -v && docker compose up -d
sleep 3
curl http://localhost:3000/rpc/hello
```

You should see:

```json
{"message": "Hello from the database!"}
```

That function *is* your endpoint. No controller, no route file, no serializer. The database is the application.

## Step 4: Your First Table (The Database-First Way)

Internal tables live in private schemas. You expose only what you choose through views in the `api` schema.

```sql
-- Private schema for account data
create schema if not exists accounts;

create table accounts.account (
  account_id bigserial primary key,
  email text not null unique,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Expose a read-only view through the API
create or replace view api.accounts as
  select account_id, email, display_name, created_at
  from accounts.account;

grant select on api.accounts to authenticated;
```

The view controls the shape of your API response. Internal columns like `updated_at` stay hidden. You can add computed columns, join across tables, or reshape data — all invisible to the consumer.

Insert a test row and query it:

```bash
# Insert directly via psql
docker compose exec postgres psql -U postgres -d myapp -c \
  "insert into accounts.account (email, display_name) values ('dev@example.com', 'Developer');"

# Query through the API (requires a valid JWT for authenticated role — 
# for now, temporarily grant select to anon for testing)
docker compose exec postgres psql -U postgres -d myapp -c \
  "grant select on api.accounts to anon;"

curl http://localhost:3000/accounts
```

## Step 5: Add a Background Job (The Supervisor Pattern)

Real applications need async work — sending emails, processing uploads, syncing data. In a database-first system, the database *is* the queue.

### Create the task table

```sql
create schema if not exists jobs;

create table jobs.task (
  task_id bigserial primary key,
  task_type text not null,
  payload jsonb not null default '{}',
  status text not null default 'pending'
    check (status in ('pending', 'running', 'completed', 'failed')),
  attempts int not null default 0,
  max_attempts int not null default 3,
  created_at timestamptz not null default now(),
  scheduled_for timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz
);

create index idx_task_pending on jobs.task (scheduled_for)
  where status = 'pending';
```

### Create a facts function

The facts function gives workers context about what to process:

```sql
create or replace function jobs.task_facts(p_task_type text, p_batch_size int default 10)
returns jsonb
language sql
stable
as $$
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
  from (
    select task_id, payload, attempts
    from jobs.task
    where task_type = p_task_type
      and status = 'pending'
      and scheduled_for <= now()
    order by scheduled_for
    limit p_batch_size
  ) t;
$$;
```

### Create the supervisor function

The supervisor claims tasks atomically and returns them to the worker:

```sql
create or replace function jobs.claim_tasks(p_task_type text, p_batch_size int default 5)
returns setof jobs.task
language sql
as $$
  update jobs.task
  set status = 'running',
      started_at = now(),
      attempts = attempts + 1
  where task_id in (
    select task_id from jobs.task
    where task_type = p_task_type
      and status = 'pending'
      and scheduled_for <= now()
    order by scheduled_for
    for update skip locked
    limit p_batch_size
  )
  returning *;
$$;
```

The `FOR UPDATE SKIP LOCKED` clause is critical — it lets multiple workers pull from the same queue without conflicts.

### Enqueue from a trigger

```sql
create or replace function accounts.on_account_created()
returns trigger
language plpgsql
as $$
begin
  insert into jobs.task (task_type, payload)
  values ('send_welcome_email', jsonb_build_object(
    'account_id', new.account_id,
    'email', new.email
  ));
  return new;
end;
$$;

create trigger trg_account_created
  after insert on accounts.account
  for each row execute function accounts.on_account_created();
```

Now every new account automatically enqueues a welcome email. A worker process calls `jobs.claim_tasks('send_welcome_email')`, sends the email, then marks the task complete.

## Step 6: Set Up Observability

Your database already knows everything about your system's health. Connect a monitoring stack to query it directly.

### Add Grafana to your compose file

```yaml
  grafana:
    image: grafana/grafana:latest
    ports:
      - "4000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
```

### Connect PostgreSQL as a data source

1. Open `http://localhost:4000` (login: admin/admin)
2. Go to Connections → Data Sources → Add PostgreSQL
3. Set host to `postgres:5432`, database to `myapp`, user to `postgres`

### Create your first panel: queue depth

Add a dashboard panel with this query:

```sql
select
  task_type,
  count(*) filter (where status = 'pending') as pending,
  count(*) filter (where status = 'running') as running,
  count(*) filter (where status = 'failed') as failed
from jobs.task
group by task_type;
```

No metrics library, no StatsD, no Prometheus exporters. The database *is* the metrics store.

## Step 7: Adding a Complete Feature (End-to-End)

Here's the full cycle for adding a "user profile update" feature:

**1. Design the schema:**

```sql
alter table accounts.account add column bio text;
alter table accounts.account add column avatar_url text;
```

**2. Write the business function:**

```sql
create or replace function api.update_profile(
  p_display_name text default null,
  p_bio text default null,
  p_avatar_url text default null
)
returns json
language plpgsql
security definer
as $$
declare
  v_account_id bigint;
begin
  -- Extract account_id from JWT claims
  v_account_id := (current_setting('request.jwt.claims', true)::json->>'account_id')::bigint;

  update accounts.account
  set display_name = coalesce(p_display_name, display_name),
      bio = coalesce(p_bio, bio),
      avatar_url = coalesce(p_avatar_url, avatar_url),
      updated_at = now()
  where account_id = v_account_id;

  return json_build_object('status', 'updated');
end;
$$;

grant execute on function api.update_profile(text, text, text) to authenticated;
```

**3. Test with curl:**

```bash
curl -X POST http://localhost:3000/rpc/update_profile \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-jwt>" \
  -d '{"p_display_name": "New Name", "p_bio": "Hello world"}'
```

**4. Add background processing if needed:**

```sql
-- Trigger to resize avatar on upload
create or replace function accounts.on_avatar_changed()
returns trigger
language plpgsql
as $$
begin
  if new.avatar_url is distinct from old.avatar_url and new.avatar_url is not null then
    insert into jobs.task (task_type, payload)
    values ('resize_avatar', jsonb_build_object(
      'account_id', new.account_id,
      'url', new.avatar_url
    ));
  end if;
  return new;
end;
$$;

create trigger trg_avatar_changed
  after update on accounts.account
  for each row execute function accounts.on_avatar_changed();
```

**5. Add a dashboard panel** to track avatar processing latency.

That's it. No application code was written. No ORM, no controller, no service layer. The database handles logic, queueing, and observability. PostgREST handles HTTP. Your workers are thin loops that call SQL functions.

## What's Next?

- Read the [Manifesto](../philosophy/manifesto.md) for the philosophy behind this approach
- Study the [Database Patterns](../patterns/database-patterns.md) for the full toolkit
- Explore [Supervisors](../architecture/workers.md) for complex workflow orchestration
- Set up [Security](../security/overview.md) for production hardening
