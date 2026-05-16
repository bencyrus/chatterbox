# PostgreSQL-Centric Architecture: Research Report

> Compiled May 2026 — current best practices for building systems where PostgreSQL is the single source of truth.

---

## Table of Contents

1. [Database-First Development Philosophy](#1-database-first-development-philosophy)
2. [PostgreSQL as a Job Queue](#2-postgresql-as-a-job-queue)
3. [LISTEN/NOTIFY for Real-Time Events](#3-listennotify-for-real-time-events)
4. [Transactional Outbox Pattern](#4-transactional-outbox-pattern)
5. [Row-Level Security for Multi-Tenancy](#5-row-level-security-for-multi-tenancy)
6. [UUID v7 vs ULID for Primary Keys](#6-uuid-v7-vs-ulid-for-primary-keys)
7. [Audit Trail Patterns](#7-audit-trail-patterns)
8. [Envelope Encryption with Cloud KMS](#8-envelope-encryption-with-cloud-kms)
9. [State Machines with Enums and Constraints](#9-state-machines-with-enums-and-constraints)
10. [Thin API Layer Philosophy](#10-thin-api-layer-philosophy)
11. [How These Patterns Compose](#11-how-these-patterns-compose)

---

## 1. Database-First Development Philosophy

### Core Idea

Database-first development treats PostgreSQL as **the** application — not just a persistence layer. All application state lives in carefully modeled datasets, and external actors (users, background jobs, AI agents) modify state through well-defined transactions. REST/RPC endpoints serve as trigger mechanisms for these transactions rather than business logic containers.

### Key Principles

- **Bring compute to data**, not data to compute clusters. Use Foreign Data Wrappers and views to minimize data movement.
- **Transaction-centric design** — every state modification is atomic and auditable within PostgreSQL itself.
- **Zero Middleware** where possible — expose tables, views, and stored routines directly as GraphQL/REST endpoints via tools like PostgREST, Hasura, or Postgraphile.
- **Schema as contract** — the database schema is the single source of truth; application layers derive from it, not the other way around.

### Trade-offs

| Benefit | Cost |
|---------|------|
| Eliminates duplication across models, validators, controllers | Requires strong SQL/PostgreSQL expertise on the team |
| Fewer moving parts to operate | Business logic in SQL can be harder to test/debug |
| ACID guarantees by default | Vendor lock-in to PostgreSQL (usually acceptable) |
| Natural audit trail via triggers | Schema migrations require more discipline |

### When to Use

- Small-to-medium teams that want to ship fast without managing many services.
- Systems where data consistency is paramount (finance, healthcare, multi-tenant SaaS).
- Projects where the team has strong PostgreSQL skills.

### When NOT to Use

- Extremely high-write-throughput systems that need horizontal write scaling beyond a single PostgreSQL instance.
- Teams with no SQL expertise who would be more productive with an ORM-first approach.

### Key Resources

- [PgDCP — PostgreSQL Data Computing Platform](https://github.com/netspective-studios/PgDCP) — reference architecture for the zero-middleware approach
- [The Database Is Your Event Bus (DebuggAI, 2025)](https://debugg.ai/resources/database-event-bus-cdc-first-architectures-postgres-outbox-inbox-debezium-2025) — CDC-first architecture with PostgreSQL
- [The API Database Architecture (Fabian Zeindl)](https://www.fabianzeindl.com/posts/the-api-database-architecture) — philosophy of eliminating HTTP-GET endpoints

---

## 2. PostgreSQL as a Job Queue

### How It Works

PostgreSQL's `SELECT ... FOR UPDATE SKIP LOCKED` clause (PostgreSQL 9.5+) enables concurrent job processing. Multiple workers query a jobs table simultaneously; `SKIP LOCKED` lets each worker atomically claim a different job without blocking others.

### Libraries

**Graphile Worker** (Node.js) — the leading PostgreSQL-native job queue:
- Uses `SKIP LOCKED` with optimized index strategies
- `LISTEN/NOTIFY` for instant job wake-up (no polling delay)
- Benchmarks: **~183,000 jobs/sec** throughput, **4.16ms average latency**
- Strategy 2 fetch algorithm: 843 jobs/sec vs 40 jobs/sec with naive approach when 100K stuck jobs exist
- Trivial job creation: `SELECT graphile_worker.add_job('task_name', '{"key": "value"}'::json)`

**pg-boss** (Node.js) — alternative with built-in scheduling, throttling, and completion events.

### Concrete Implementation

```sql
-- Minimal job queue table
CREATE TABLE job_queue (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    queue_name  TEXT NOT NULL DEFAULT 'default',
    payload     JSONB NOT NULL DEFAULT '{}',
    status      TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'running', 'completed', 'failed')),
    run_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    locked_at   TIMESTAMPTZ,
    locked_by   TEXT,
    attempts    INT NOT NULL DEFAULT 0,
    max_attempts INT NOT NULL DEFAULT 3
);

CREATE INDEX idx_job_queue_fetch ON job_queue (run_at)
    WHERE status = 'pending';

-- Worker claims a job
WITH next_job AS (
    SELECT id FROM job_queue
    WHERE status = 'pending' AND run_at <= now()
    ORDER BY run_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED
)
UPDATE job_queue SET
    status = 'running',
    locked_at = now(),
    locked_by = 'worker-1',
    attempts = attempts + 1
FROM next_job
WHERE job_queue.id = next_job.id
RETURNING *;
```

### Trade-offs: PostgreSQL vs Redis/RabbitMQ

| Factor | PostgreSQL Queue | Redis/RabbitMQ |
|--------|-----------------|----------------|
| Throughput | Hundreds to low thousands jobs/sec | Tens of thousands+ jobs/sec |
| Consistency | Full ACID, jobs never lost | At-most-once or at-least-once depending on config |
| Operational cost | Zero — uses existing database | Additional service to provision, monitor, backup |
| Latency | 2-4ms (with LISTEN/NOTIFY) | Sub-millisecond |
| Complex routing | Limited | RabbitMQ excels (topic exchanges, dead letters) |
| Monitoring | No built-in GUI (Graphile Worker) | Rich dashboards available |

### When to Use PostgreSQL Queues

- You already run PostgreSQL and handle < 10,000 jobs/sec
- Jobs are transactional (create job + business write atomically)
- You want to minimize infrastructure

### When to Use a Dedicated Broker

- Sustained throughput > 10,000 jobs/sec
- Complex routing patterns (fan-out, topic-based)
- Cross-platform consumers beyond your primary language

### Key Resources

- [Graphile Worker Docs](https://worker.graphile.org/docs) — architecture and performance
- [Postgres as a Queue (TechPlained)](https://www.techplained.com/postgres-as-queue) — pattern walkthrough
- [PostgreSQL Job Queues with SKIP LOCKED (Gold Lapel)](https://goldlapel.com/grounds/replication-scaling-cloud/postgresql-job-queue-skip-locked) — benchmarks and implementation
- [I Removed Redis From My Stack (DEV Community)](https://dev.to/aws-builders/i-removed-redis-from-my-stack-and-used-postgresql-for-job-queues-instead-2lp5) — real-world migration story

---

## 3. LISTEN/NOTIFY for Real-Time Events

### How It Works

PostgreSQL's built-in publish-subscribe mechanism delivers notifications via the database wire protocol. Applications subscribe with `LISTEN channel_name` and publishers send with `NOTIFY channel_name, 'payload'`. The server pushes messages asynchronously — no polling required.

### Key Patterns

```sql
-- Publisher: trigger-based notification on row change
CREATE OR REPLACE FUNCTION notify_change() RETURNS trigger AS $$
BEGIN
    PERFORM pg_notify(
        'table_changes',
        json_build_object(
            'table', TG_TABLE_NAME,
            'action', TG_OP,
            'id', NEW.id
        )::text
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER orders_notify
    AFTER INSERT OR UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION notify_change();

-- Subscriber (application-level pseudo-code):
-- conn.execute("LISTEN table_changes")
-- loop: notification = conn.wait_for_notify()
```

### Critical Characteristics

| Property | Behavior |
|----------|----------|
| Durability | **Not durable** — if no listener is connected, notifications are lost forever |
| Delivery guarantee | At-most-once |
| Transactionality | NOTIFY inside a transaction fires only on COMMIT (no ghost events from rollbacks) |
| Payload limit | 8,000 bytes |
| Ordering | Not guaranteed across channels |
| Deduplication | Identical payloads on the same channel within one transaction collapse to a single notification |
| Connection pooling | **PgBouncer transaction mode breaks LISTEN** — use a dedicated unpooled connection |

### Best Practices

1. Use NOTIFY as a **doorbell/hint**, not a guaranteed delivery system.
2. Keep payloads minimal — send a reference ID, fetch full data on the receiving side.
3. Design listeners to tolerate missed events — perform a full state read on reconnect.
4. Maintain a **dedicated, unpooled connection** for listener processes.
5. Keep transactions short to minimize notification delivery delays.

### When to Use

- Cache invalidation signals
- Job queue wake-ups (complement to SKIP LOCKED polling)
- Live dashboard updates, badge count refreshes
- Internal service coordination where occasional missed events are acceptable

### When NOT to Use

- Guaranteed delivery is required (use outbox + message broker instead)
- High-volume event streams (> thousands/sec per channel)
- Cross-datacenter event propagation

### Key Resources

- [PostgreSQL LISTEN/NOTIFY Guide (JusDB)](https://www.jusdb.com/blog/postgresql-listen-notify-realtime-events) — comprehensive patterns and limitations
- [LISTEN/NOTIFY: When It's Enough (Koder.ai)](https://koder.ai/blog/postgresql-listen-notify-live-updates) — decision framework
- [PostgreSQL LISTEN/NOTIFY Pub/Sub (Gold Lapel)](https://goldlapel.com/grounds/replication-scaling-cloud/postgresql-listen-notify-pubsub) — comparison with Redis Pub/Sub
- [PostgreSQL Official NOTIFY Docs](https://www.postgresql.org/docs/current/sql-notify.html)

---

## 4. Transactional Outbox Pattern

### The Problem It Solves

The **dual-write problem**: when you need to both update the database and publish an event (e.g., to Kafka), you cannot do both atomically. If the database write succeeds but the event publish fails (or vice versa), your system is inconsistent.

### How It Works

Write both business data **and** the event to the database in a single transaction. A separate relay process reads the outbox table and forwards events to the message broker.

### Schema Implementation

```sql
CREATE TABLE outbox_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type  TEXT NOT NULL,        -- e.g., 'order', 'user'
    aggregate_id    TEXT NOT NULL,        -- e.g., the order ID
    event_type      TEXT NOT NULL,        -- e.g., 'order.created'
    payload         JSONB NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at    TIMESTAMPTZ,          -- NULL until successfully relayed
    retry_count     INT NOT NULL DEFAULT 0
);

-- Partial index for efficient polling of unpublished events
CREATE INDEX idx_outbox_unpublished
    ON outbox_events (created_at)
    WHERE published_at IS NULL;

-- Usage: atomic business write + event
BEGIN;
    INSERT INTO orders (id, customer_id, total) VALUES (...);
    INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
    VALUES ('order', '123', 'order.created', '{"total": 99.99}'::jsonb);
COMMIT;
```

### Relay Approaches

| Approach | Mechanism | Latency | DB Load | Complexity |
|----------|-----------|---------|---------|------------|
| **Polling** | Worker queries `WHERE published_at IS NULL` on interval | Seconds | Higher (repeated queries) | Low |
| **CDC (Debezium)** | Streams WAL changes via logical replication | Near real-time | Lower | Medium-High |
| **Logical Replication (outboxd)** | Lightweight WAL listener without full CDC | Near real-time | Low | Medium |
| **LISTEN/NOTIFY + polling** | NOTIFY as wake-up hint, poll as fallback | Low | Low | Low-Medium |

### Operational Considerations

- **The outbox is a ledger, not a queue.** High write rates cause autovacuum lag and table bloat if not cleaned up.
- **CDC replication slot lag** can prevent WAL recycling and fill disk space.
- **Periodic cleanup** is essential — archive or delete published events.
- Design consumers to be **idempotent** (at-least-once delivery semantics).

### Libraries & Tools

- [pg-transactional-outbox](https://github.com/Zehelein/pg-transactional-outbox) — TypeScript, at-least-once with exactly-once processing
- [ulak](https://pgxn.org/dist/ulak/) — PostgreSQL extension with 6 protocol targets (HTTP, Kafka, MQTT, Redis, AMQP, NATS), circuit breaker, dead letter queues
- [poutbox](https://github.com/gosom/poutbox) — Go, polling + logical replication modes
- [outboxd](https://github.com/pivovarit/outboxd) — Go, lightweight WAL-based relay (2026)
- [Debezium](https://debezium.io/) — full CDC platform, PostgreSQL connector

### Key Resources

- [Transactional Outbox Pattern (JusDB)](https://www.jusdb.com/blog/transactional-outbox-pattern-event-publishing) — pattern explained with schema
- [Outbox Pattern with Debezium and Kafka (The Honest Coder)](https://thehonestcoder.com/outbox-pattern-debezium-kafka/) — CDC implementation guide
- [The Transactional Outbox Is Not a Queue (Tiare Balbi)](https://www.tiarebalbi.com/en/blog/the-transactional-outbox-is-not-a-queue) — operational pitfalls

---

## 5. Row-Level Security for Multi-Tenancy

### Core Pattern

RLS enforces tenant isolation at the database level using **runtime session variables**. Every query is automatically filtered by the current tenant, making it impossible for application bugs to leak data across tenants.

```sql
-- Enable RLS on a tenant-scoped table
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

-- Policy: rows are visible only to the current tenant
CREATE POLICY tenant_isolation ON documents
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

-- Separate write policy with WITH CHECK
CREATE POLICY tenant_write ON documents
    FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.current_tenant')::UUID);

-- Set tenant context at the start of each request
SET LOCAL app.current_tenant = 'tenant-uuid-here';
```

### Best Practices

1. **One low-privilege role** with `BYPASSRLS = false` — do not create per-tenant database roles.
2. **Set context via `SET LOCAL`** — scoped to the current transaction, auto-cleared on commit/rollback.
3. **Pass JWT claims** via `SET LOCAL request.jwt.claims` for integration with PostgREST/Hasura.
4. **Write separate policies** for SELECT, INSERT, UPDATE, DELETE operations.
5. **Create composite indexes** mirroring policy predicates (e.g., `(tenant_id, created_at)`).
6. **Test with pgTAP** — simulate real session contexts for both positive and negative cases.
7. **Enable RLS before production launch** — retrofitting on live tables is risky.

### Performance Impact

- RLS adds **minimal overhead** — policies participate in query planning and use indexes like hand-written WHERE clauses.
- Composite indexes on `(tenant_id, ...)` typically recover any cost.
- For large tenants, consider **hash-partitioned tables by tenant_id** with Citus or PostgreSQL native partitioning.

### Architectural Alternatives

| Model | Isolation | Scale | Operations |
|-------|-----------|-------|------------|
| **RLS on shared tables** | Logical | Best for < 10K tenants | Simplest |
| **Schema-per-tenant** | Stronger | Per-tenant indexing possible | Painful at > 100 tenants |
| **Database-per-tenant** | Strongest | Regulatory requirements | Operationally expensive |

**2025 consensus:** Start with RLS on shared tables. Add partitioning as you scale.

### Security Caveats

- RLS is a **safety net against forgotten WHERE clauses**, not a replacement for authentication.
- Superusers and table owners bypass RLS by default — use `FORCE ROW LEVEL SECURITY` on table owners.
- Test for privilege creep with negative test cases.

### Key Resources

- [AWS Prescriptive Guidance: RLS Recommendations](https://docs.aws.amazon.com/prescriptive-guidance/latest/saas-multitenant-managed-postgresql/rls.html) — authoritative best practices
- [Postgres Multitenancy 2025 (DebuggAI)](https://debugg.ai/resources/postgres-multitenancy-rls-vs-schemas-vs-separate-dbs-performance-isolation-migration-playbook-2025) — RLS vs schemas vs separate DBs
- [Fine-Grained RLS for SaaS (Puzzledge)](https://blog.puzzledge.org/2025/05/12/how-we-designed-fine-grained-row-level-security-in-postgresql/) — production design patterns
- [RLS in Practice (QueryPlane)](https://queryplane.com/docs/blog/postgres-row-level-security-in-practice) — practical implementation guide

---

## 6. UUID v7 vs ULID for Primary Keys

### The Problem with UUID v4

Random UUIDs cause severe B-tree index degradation. Each insert hits a random leaf page, causing cache misses and random I/O. At 100M rows, UUID v4 achieves only **38% of the insert throughput** of time-ordered alternatives.

### UUID v7 (RFC 9562, 2024)

| Property | Value |
|----------|-------|
| Format | 128-bit, standard UUID layout |
| Timestamp | First 48 bits — Unix epoch milliseconds |
| Randomness | ~74 bits |
| Sortability | Chronological (lexicographic sort = time sort) |
| PostgreSQL type | Native `uuid` type |
| PostgreSQL 18+ | Built-in `uuidv7()` function |
| Pre-PG18 | Use `pg_uuidv7` extension |

### ULID

| Property | Value |
|----------|-------|
| Format | 128-bit, 26-char Crockford Base32 string |
| Timestamp | First 48 bits — Unix epoch milliseconds |
| Randomness | 80 bits |
| Sortability | Lexicographic and chronological |
| PostgreSQL type | Stored as `TEXT` or `BYTEA` (no native type) |

### Performance Benchmarks (PostgreSQL 16, 100M rows)

| ID Type | INSERT Throughput | Index Fragmentation |
|---------|------------------|---------------------|
| BIGSERIAL | 100% (baseline) | Minimal |
| UUID v7 | 97% | Minimal |
| ULID | 94% | Minimal |
| UUID v4 | 38% | High |

UUID v7 achieves ~3,420 TPS vs UUID v4's ~2,670 TPS in absolute terms. The time-sorted prefix ensures sequential index appends rather than random scatter.

### Recommendation

**Use UUID v7 for new PostgreSQL projects.** Rationale:
- RFC standardized (RFC 9562, 2024)
- Native PostgreSQL 18+ support (`uuidv7()`)
- Fits the existing `uuid` column type (no storage overhead vs UUID v4)
- Time-extractable: `uuid_extract_timestamp()` in PG18+
- Near-zero index fragmentation at scale

Use ULID only if you need human-readable, copy-pasteable identifiers and accept the text storage cost.

### Migration Path

```sql
-- PostgreSQL 18+
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    ...
);

-- PostgreSQL 13-17 with pg_uuidv7 extension
CREATE EXTENSION IF NOT EXISTS pg_uuidv7;
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    ...
);
```

### Key Resources

- [UUID v4 vs ULID vs TSID: B-Tree Impact at 100M Records (Michal Drozd)](https://www.michal-drozd.com/en/blog/uuid-ulid-tsid-postgresql/) — benchmark methodology and results
- [UUIDv7 Comes to PostgreSQL 18 (Nile)](https://thenile.dev/blog/uuidv7) — native support details
- [UUID Benchmark War (Ardent Performance)](https://ardentperf.com/2024/02/03/uuid-benchmark-war/) — thorough performance analysis
- [PostgreSQL 18 UUID Functions Docs](https://www.postgresql.org/docs/current/static/functions-uuid.html)

---

## 7. Audit Trail Patterns

### Approach Comparison

| Factor | Trigger-Based | Application-Level | CDC (Logical Replication) |
|--------|--------------|-------------------|--------------------------|
| Bypass risk | **Impossible** to bypass | Developers can bypass via direct SQL | Impossible to bypass |
| Capture scope | All changes from any source | Only changes through the app | All WAL changes |
| Before/after values | Full JSONB diff | Must be explicitly captured | Full row images |
| Performance impact | Per-write overhead | Minimal DB impact | Minimal (reads WAL) |
| Schema coupling | Trigger per table | Decoupled | Decoupled |
| Complexity | Low-Medium | Low | Medium-High |

### Recommended: Trigger-Based Auditing

Trigger-based auditing is the strongest choice for a PostgreSQL-centric architecture because it **cannot be bypassed** regardless of how data is modified.

### Implementation

```sql
-- Audit log table (append-only)
CREATE TABLE audit_log (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name  TEXT NOT NULL,
    operation   TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    row_id      TEXT NOT NULL,
    old_data    JSONB,
    new_data    JSONB,
    changed_by  TEXT DEFAULT current_setting('app.current_user', true),
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    tenant_id   UUID DEFAULT current_setting('app.current_tenant', true)::UUID
);

-- Partition by month for manageability at scale
CREATE TABLE audit_log_y2026m05 PARTITION OF audit_log
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

-- Generic trigger function (works on any table)
CREATE OR REPLACE FUNCTION audit_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, row_id, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.id::text, to_jsonb(NEW));
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, row_id, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.id::text, to_jsonb(OLD), to_jsonb(NEW));
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, row_id, old_data)
        VALUES (TG_TABLE_NAME, TG_OP, OLD.id::text, to_jsonb(OLD));
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Attach to any table
CREATE TRIGGER audit_orders
    AFTER INSERT OR UPDATE OR DELETE ON orders
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();
```

### Best Practices

1. **Append-only** — never allow UPDATE or DELETE on the audit table.
2. **Partition by time** (month or quarter) once you reach millions of rows.
3. **Use `current_setting('app.current_user', true)`** to capture the application-level user via session variables.
4. **Store JSONB diffs** for space efficiency on wide tables (optional: compute diff in trigger).
5. **Consider pgAudit** for SQL-level audit logging alongside row-level triggers (complementary, not replacement).

### Key Resources

- [Why Application-Layer Audit Trails Fail (DEV Community)](https://dev.to/kenzura/why-application-layer-audit-trails-fail-and-how-postgresql-triggers-fix-it-3h4h) — failure modes of app-level auditing
- [PostgreSQL Audit Logging Triggers (Vlad Mihalcea)](https://vladmihalcea.com/postgresql-audit-logging-triggers) — JSONB before/after pattern
- [Audit Trigger (PostgreSQL Wiki)](https://wiki.postgresql.org/wiki/Audit_trigger) — community reference implementation
- [Two Sigma audit.sql](https://github.com/twosigma/postgresql-contrib/blob/master/audit.sql) — production-grade audit trigger

---

## 8. Envelope Encryption with Cloud KMS

### The Pattern

Envelope encryption uses a two-layer key hierarchy to protect data at rest:

```
┌─────────────────────────────────────────────┐
│                  Cloud KMS                   │
│  ┌─────────────────────────────────────┐    │
│  │  KEK (Key Encryption Key)           │    │
│  │  - Never leaves KMS                 │    │
│  │  - Wraps/unwraps DEKs              │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
                    │
              wraps/unwraps
                    │
┌─────────────────────────────────────────────┐
│            Application Layer                 │
│  ┌─────────────────────────────────────┐    │
│  │  DEK (Data Encryption Key)          │    │
│  │  - Generated locally per file       │    │
│  │  - Encrypts actual data             │    │
│  │  - Stored encrypted (wrapped)       │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

### Why Not Encrypt Directly with KMS?

- KMS has **payload size limits** (e.g., Google Cloud KMS: 64 KiB max)
- Each KMS call adds **network latency** (~5-20ms)
- KMS calls have **cost per operation** — envelope encryption reduces calls by ~10,000x for bulk operations
- A single KEK can protect millions of DEKs

### Implementation with PostgreSQL

```sql
-- File metadata with encryption info
CREATE TABLE file_uploads (
    id              UUID PRIMARY KEY DEFAULT uuidv7(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    filename        TEXT NOT NULL,
    content_type    TEXT NOT NULL,
    size_bytes      BIGINT NOT NULL,

    -- Storage location (cloud object store)
    storage_bucket  TEXT NOT NULL,
    storage_key     TEXT NOT NULL,

    -- Encryption metadata
    encrypted_dek   BYTEA NOT NULL,           -- DEK wrapped by KEK
    kms_key_id      TEXT NOT NULL,             -- which KEK was used
    encryption_algo TEXT NOT NULL DEFAULT 'AES-256-GCM',
    key_version     INT NOT NULL DEFAULT 1,    -- for key rotation tracking

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      UUID NOT NULL REFERENCES users(id)
);
```

### Encryption Flow

**Upload (encrypt):**
1. Generate a random 32-byte DEK locally
2. Encrypt the file with the DEK using AES-256-GCM
3. Call KMS to wrap (encrypt) the DEK with the KEK
4. Upload encrypted file to object storage (S3/GCS)
5. Store wrapped DEK + metadata in PostgreSQL

**Download (decrypt):**
1. Read file metadata from PostgreSQL (wrapped DEK, storage location)
2. Call KMS to unwrap (decrypt) the DEK
3. Fetch encrypted file from object storage
4. Decrypt file locally with the unwrapped DEK
5. Stream plaintext to the client

### Best Practices

1. **One DEK per file** — limits blast radius of any single key compromise.
2. **Never store plaintext DEKs** — only wrapped (encrypted) DEKs persist.
3. **Key rotation**: rotate the KEK in KMS; re-wrap existing DEKs with the new KEK (no need to re-encrypt files).
4. **Map encryption keys to data classifications** — different KEKs for different sensitivity levels.
5. **Use established libraries** — Google Tink, AWS Encryption SDK — don't roll your own crypto.

### Cloud Provider Libraries

| Provider | Library | KMS Service |
|----------|---------|-------------|
| GCP | [Tink](https://developers.google.com/tink) | Cloud KMS |
| AWS | [AWS Encryption SDK](https://docs.aws.amazon.com/encryption-sdk/latest/developer-guide/) | AWS KMS |
| Azure | Azure SDK KeyVault Crypto | Azure Key Vault |

### Key Resources

- [Google Cloud Envelope Encryption](https://cloud.google.com/kms/docs/envelope-encryption) — canonical reference
- [Client-Side Encryption with Tink and Cloud KMS](https://cloud.google.com/kms/docs/client-side-encryption) — GCP implementation
- [AWS Well-Architected: Enforce Encryption at Rest](https://docs.aws.amazon.com/wellarchitected/2023-10-03/framework/sec_protect_data_rest_encrypt.html) — AWS patterns
- [Envelope Encryption: The Security Pattern Every Developer Should Know](https://n.demir.io/articles/envelope-encryption-the-security-pattern-every-cloud-developer-should-know/) — comprehensive overview

---

## 9. State Machines with Enums and Constraints

### Core Pattern

Enforce valid state transitions at the database level so no application code, batch job, or admin query can put a record into an invalid state.

### Approach 1: Enum + Transitions Table (Recommended)

```sql
-- Define states and events as enums
CREATE TYPE order_status AS ENUM (
    'draft', 'submitted', 'approved', 'processing',
    'shipped', 'delivered', 'cancelled'
);

CREATE TYPE order_event AS ENUM (
    'submit', 'approve', 'reject', 'start_processing',
    'ship', 'deliver', 'cancel'
);

-- Valid transitions mapping
CREATE TABLE order_transitions (
    current_state  order_status NOT NULL,
    event          order_event NOT NULL,
    next_state     order_status NOT NULL,
    PRIMARY KEY (current_state, event)
);

INSERT INTO order_transitions VALUES
    ('draft',      'submit',           'submitted'),
    ('submitted',  'approve',          'approved'),
    ('submitted',  'reject',           'draft'),
    ('submitted',  'cancel',           'cancelled'),
    ('approved',   'start_processing', 'processing'),
    ('approved',   'cancel',           'cancelled'),
    ('processing', 'ship',             'shipped'),
    ('shipped',    'deliver',          'delivered');

-- Transition function
CREATE OR REPLACE FUNCTION apply_order_event(
    _current order_status, _event order_event
) RETURNS order_status AS $$
    SELECT next_state FROM order_transitions
    WHERE current_state = _current AND event = _event;
$$ LANGUAGE sql STABLE;

-- BEFORE UPDATE trigger to enforce transitions
CREATE OR REPLACE FUNCTION enforce_order_transition()
RETURNS TRIGGER AS $$
DECLARE
    valid_next order_status;
BEGIN
    IF OLD.status = NEW.status THEN
        RETURN NEW;  -- no state change, allow
    END IF;

    SELECT next_state INTO valid_next
    FROM order_transitions
    WHERE current_state = OLD.status
      AND next_state = NEW.status;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid state transition: % -> %',
            OLD.status, NEW.status;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_order_transition
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION enforce_order_transition();
```

### Approach 2: CHECK Constraints (Simpler, Less Flexible)

```sql
-- For truly simple state machines
CREATE TABLE tasks (
    id     UUID PRIMARY KEY DEFAULT uuidv7(),
    status TEXT NOT NULL DEFAULT 'pending'
           CHECK (status IN ('pending', 'running', 'completed', 'failed'))
);
```

### Enum vs CHECK Constraints

| Factor | PostgreSQL Enum | CHECK + Text |
|--------|----------------|--------------|
| Storage | 4 bytes (OID) | Variable (full text) |
| Type safety | Strong — invalid values rejected | Via constraint only |
| Adding values | `ALTER TYPE ... ADD VALUE` (no rewrite) | Modify constraint (can use `NOT VALID`) |
| Removing values | Requires recreating the type | Easy constraint modification |
| Renaming values | Supported (PG 10+) | Just update the constraint |
| Migration pain | Higher for removals | Consistently low |

### When to Use Each

- **Enum + transitions table**: core business entities with well-defined lifecycle (orders, invoices, tickets).
- **CHECK constraints**: simple status fields that may evolve (feature flags, task states).
- **Application-level only**: avoid — any direct SQL access bypasses the rules.

### Key Resources

- [Implementing State Machines in PostgreSQL (Felix Geisendörfer)](https://felixge.de/2017/07/27/implementing-state-machines-in-postgresql/) — foundational article
- [Versioned FSM with PostgreSQL (Raphael Medaer)](https://raphael.medaer.me/2019/06/12/pgfsm.html) — transitions table pattern
- [Native Enums or CHECK Constraints? (Close.com)](https://making.close.com/posts/native-enums-or-check-constraints-in-postgresql) — detailed comparison
- [We Need to Talk About ENUMs (boringSQL)](https://boringsql.com/posts/postgresql-enums/) — enum internals and gotchas

---

## 10. Thin API Layer Philosophy

### Core Idea

Instead of building custom CRUD endpoints, let the database schema **be** the API. Tools like PostgREST and Hasura automatically generate REST/GraphQL APIs by introspecting PostgreSQL schemas. The application developer focuses on:

1. **Schema design** — tables, views, functions
2. **Security** — RLS policies, role grants
3. **Business logic** — stored procedures or thin server-side functions for writes

### PostgREST Architecture

```
Client → PostgREST → PostgreSQL
           │
           ├── Tables → GET /resource, POST /resource
           ├── Views  → GET /materialized_views
           ├── RPC    → POST /rpc/function_name
           └── RLS    → Authorization (transparent)
```

PostgREST serves ~2,000+ req/sec on low-end hardware. Features include:
- Automatic filtering, sorting, pagination
- Field selection (`?select=id,name`)
- Embedded relations (`?select=*,comments(*)`)
- JWT-based auth mapped to PostgreSQL roles
- Auto-generated OpenAPI schema

### The Split Architecture

The pragmatic approach from the community splits read and write operations:

| Operation | Handler | Rationale |
|-----------|---------|-----------|
| **Reads (GET)** | PostgREST / Hasura | Declarative, auto-generated, fast |
| **Writes (POST/PUT/DELETE)** | Custom backend | Business logic, validation, side effects |

This gives you the productivity of auto-generated APIs for the ~80% of endpoints that are reads, while retaining full control over mutations.

### Hasura's Approach

Hasura functions as a "JIT compiler" for GraphQL — it converts incoming queries to optimized SQL and delegates to PostgreSQL. Business logic is handled via:
- **Event triggers** — fire webhooks on data changes
- **Actions** — custom REST endpoints for mutations
- **Remote schemas** — federate with other GraphQL services
- **Stored procedures** — PostgreSQL functions exposed as mutations

### Trade-offs

| Benefit | Cost |
|---------|------|
| Eliminates 80%+ of backend CRUD code | Schema changes = API changes (can be a feature or bug) |
| Database schema is the single source of truth | Complex business logic still needs application code |
| Built-in performance (query planner optimization) | Debugging moves from application logs to SQL/DB logs |
| Security via battle-tested PostgreSQL RLS | Team needs PostgreSQL expertise, not just ORM knowledge |

### Key Resources

- [The API Database Architecture (Fabian Zeindl)](https://www.fabianzeindl.com/posts/the-api-database-architecture) — philosophy manifesto
- [PostgREST Documentation](https://docs.postgrest.org/en/stable) — official reference
- [PostgREST: Revolutionizing Web Development (Marmelab, 2024)](https://marmelab.com/blog/2024/11/04/postgrest-revolutionizing-web-development-with-instant-apis) — modern perspective
- [How Hasura Works](https://hasura.io/blog/how-hasura-works) — JIT compiler analogy and design philosophy
- [PostgREST REST API Guide (Better Stack)](https://betterstack.com/community/guides/databases/postgresql-rest-api/) — hands-on tutorial

---

## 11. How These Patterns Compose

These patterns are not independent — they form a cohesive architecture when combined:

```
┌────────────────────────────────────────────────────────────────┐
│                        Clients                                  │
└────────────────────┬───────────────────────────────────────────┘
                     │
┌────────────────────▼───────────────────────────────────────────┐
│              Thin API Layer (PostgREST / Hasura)                │
│   Reads: auto-generated from schema                             │
│   Writes: thin handlers → SQL transactions                      │
│   Auth: JWT → SET LOCAL → RLS enforces tenant isolation         │
└────────────────────┬───────────────────────────────────────────┘
                     │
┌────────────────────▼───────────────────────────────────────────┐
│                    PostgreSQL (Single Source of Truth)           │
│                                                                 │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Tables       │  │ RLS Policies │  │ State Machine        │  │
│  │ (UUID v7 PKs)│  │ (tenant_id)  │  │ Triggers + Enums     │  │
│  └──────┬──────┘  └──────────────┘  └──────────────────────┘  │
│         │                                                       │
│  ┌──────▼──────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Audit        │  │ Outbox Table │  │ Job Queue Table      │  │
│  │ Triggers     │  │ (events)     │  │ (SKIP LOCKED)        │  │
│  └─────────────┘  └──────┬───────┘  └──────────┬───────────┘  │
│                          │                      │               │
│  ┌───────────────────────▼──────────────────────▼───────────┐  │
│  │              LISTEN/NOTIFY (doorbell)                      │  │
│  └───────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
                     │                      │
        ┌────────────▼──────┐    ┌──────────▼──────────┐
        │ Outbox Relay       │    │ Graphile Worker      │
        │ (CDC or polling)   │    │ (background jobs)    │
        └────────────────────┘    └─────────────────────┘
                     │
        ┌────────────▼──────────────────────────────────┐
        │ File Storage (S3/GCS)                          │
        │ Envelope Encryption: DEK per file              │
        │ Wrapped DEK stored in PostgreSQL               │
        │ KEK managed by Cloud KMS                       │
        └───────────────────────────────────────────────┘
```

### Composition Flow

1. **Request arrives** → thin API layer authenticates via JWT, sets `app.current_tenant` and `app.current_user` session variables.

2. **RLS activates** → every query is automatically scoped to the current tenant. No WHERE clause needed in application code.

3. **State transitions** → updates to business entities are validated by BEFORE triggers checking the transitions table. Invalid transitions raise exceptions before data is written.

4. **Audit trail** → AFTER triggers on all business tables log old/new values to the append-only audit_log table, capturing the actor from session variables.

5. **Outbox events** → write handlers insert events into the outbox table in the same transaction as business data. Dual-write problem eliminated.

6. **LISTEN/NOTIFY** → the outbox insert fires a NOTIFY to wake up the relay process. The job queue uses NOTIFY to wake idle workers. Both use it as a hint, not a guarantee.

7. **Background processing** → Graphile Worker picks up jobs via SKIP LOCKED. Jobs might include: relay outbox events, process file uploads, send emails, run reports.

8. **File encryption** → when uploading files, the worker generates a DEK, encrypts the file, wraps the DEK via Cloud KMS, stores the encrypted file in object storage, and saves the wrapped DEK in PostgreSQL.

9. **Primary keys** → all tables use UUID v7 for time-ordered, index-friendly, globally unique identifiers. Extractable timestamps provide built-in "created_at" semantics.

### Key Architectural Properties

- **Single database, maximum consistency** — no distributed transactions, no eventual consistency headaches for core operations.
- **Defense in depth** — RLS prevents data leaks, triggers prevent invalid states, audit logs provide forensic capability.
- **Minimal infrastructure** — PostgreSQL + thin API server + workers. No Redis, no Kafka, no separate auth service (until you need them).
- **Clear scaling path** — when a pattern hits its limits (e.g., job throughput > 10K/sec), swap in a dedicated service for that specific concern while keeping the rest of the architecture intact.
