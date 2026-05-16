# Observability

## Philosophy: Observe, Don't Test

In a database-first system, the most powerful diagnostic tool is a `SELECT` statement.

Traditional testing predicts behavior in synthetic environments — mock databases, fake queues, contrived inputs. It answers: *does this code do what I think it does, in a scenario I imagined?* Observability answers a better question: *what is the system actually doing, right now, with real data?*

> "We don't rely on traditional testing. We observe. Logs and metrics tell the truth about your live system."

This doesn't mean "no quality assurance." It means the system's architecture makes quality continuously visible rather than periodically sampled:

- **Facts functions ARE your tests.** Call them anytime in production with no side effects. A supervisor function that returns `(has_success, num_failures, num_attempts)` isn't just operational logic — it's a live assertion about system state.
- **The database IS your audit trail.** Every decision, every state transition, every error is recorded as an append-only fact. You don't need to reproduce a bug — you query what happened.
- **Dashboards query the source of truth directly.** No aggregation pipelines, no ETL jobs, no stale materialized views. The dashboard reads the same tables your application writes to.

The philosophical shift is this: testing validates a *model* of your system. Observability reveals the *system itself*. In an architecture where all state lives in one queryable place, observability is the stronger guarantee.

---

## The Database as the Primary Observability Surface

The most important metrics in a database-first system come from SQL queries, not application-level instrumentation. The database already knows everything — you just have to ask.

### Queue Health

```sql
-- Current queue depth (pending work)
select count(*) from queues.task t
where not exists (
    select 1 from queues.task_completed c where c.task_id = t.task_id
  )
  and not exists (
    select 1 from queues.task_lease l
    where l.task_id = t.task_id and l.expires_at > now()
  );

-- Error rate (last hour)
select count(*) from queues.error
where created_at > now() - interval '1 hour';

-- Task latency (avg time from enqueue to completion)
select avg(c.completed_at - t.enqueued_at)
from queues.task_completed c
join queues.task t using (task_id)
where c.completed_at > now() - interval '1 hour';
```

### Supervisor Diagnostics

```sql
-- What does the supervisor see right now?
select comms.send_email_supervisor_facts(12345);
-- Returns: (has_success, num_failures, num_attempts)

-- What's stuck?
select * from comms.send_email_task t
where comms.is_send_email_stuck(t.send_email_task_id);
```

These aren't monitoring queries bolted on after the fact. They're the same functions the system uses to make decisions. When you call a supervisor facts function from a dashboard, you see exactly what the worker sees. No translation layer, no impedance mismatch between "what the monitoring says" and "what the system believes."

---

## Architecture: Grafana Cloud + PostgreSQL Data Source

The observability stack has four components:

1. **Grafana Alloy** — auto-discovers all containers via the Docker socket, ships logs to Loki without per-service configuration
2. **PDC Agent** — an outbound SSH tunnel that allows Grafana Cloud to query a private PostgreSQL instance directly
3. **Grafana Cloud Loki** — centralized log storage and search
4. **Grafana Cloud PostgreSQL Data Source** — dashboard panels that execute SQL queries against the live database

This architecture has a key property: **business dashboards and operational dashboards use the same data source.** A "users created this week" panel and a "stuck tasks" panel both query PostgreSQL. No distinction between business intelligence and operational monitoring — because there's no distinction in where the data lives.

A read-only database user (`grafana_reader`) provides safe access. It can read every schema but write nothing. Dashboard queries are just `SELECT` — they cannot interfere with the running system.

---

## Structured Logging

All services emit structured JSON to stdout. No log files, no syslog, no custom transports:

```json
{
  "timestamp": "2026-01-15T10:30:00Z",
  "level": "info",
  "service": "worker",
  "request_id": "abc-123-def",
  "message": "task completed",
  "fields": {
    "task_id": 456,
    "task_type": "email",
    "duration_ms": 230
  }
}
```

Grafana Alloy collects these from every container's stdout stream and forwards them to Loki. Adding a new service requires zero observability configuration — deploy the container and its logs appear in Grafana within seconds.

### Request Correlation

Every request gets a traceable identity:

- **Caddy** generates an `X-Request-ID` (UUID) on every inbound request
- The header is forwarded to all downstream services — gateway, PostgREST, workers
- Every log entry includes the request ID

When something fails, filter Loki by `request_id` and you see every log line from every service that touched that request, in order. End-to-end traceability without a distributed tracing framework.

---

## Health Checks

### Philosophy

Health checks are simple liveness probes, not deep dependency audits. Each component reports its own health independently:

| Component | Health check | Method |
|---|---|---|
| PostgreSQL | `pg_isready` | TCP + protocol check |
| File service | `GET /healthz` | HTTP 200 |
| Backup service | `GET /health` | HTTP 200 |
| Worker | `restart: unless-stopped` | Process-level (no HTTP endpoint) |

A health check answers one question: *is this process alive and able to accept work?* It should not cascade into checking downstream dependencies — that creates brittle chains where a slow database response causes the entire stack to report unhealthy.

### Cascade Startup

Services declare `depends_on: postgres: condition: service_healthy` in their compose configuration. The database must be healthy before anything else starts. This isn't just operational hygiene — it's a reflection of the architecture. PostgreSQL is the brain. Nothing functions without it, so nothing should try.

---

## The Durable Error Audit Trail

Errors aren't just logged to a stream that scrolls off screen — they're persisted as first-class data in the database:

```sql
create table queues.error (
  error_id   bigserial primary key,
  task_id    bigint references queues.task(task_id),
  error_message text not null,
  created_at timestamptz not null default now()
);
```

This changes error analysis from a log search into a SQL query. Join errors with tasks, correlate failures with business entities, identify patterns over time, and build alerting dashboards — all with standard SQL.

```sql
-- Error distribution by task type (last 24 hours)
select t.task_type, count(*) as error_count
from queues.error e
join queues.task t using (task_id)
where e.created_at > now() - interval '24 hours'
group by t.task_type
order by error_count desc;
```

---

## What Makes a Good Dashboard

The best dashboards in this paradigm query PostgreSQL directly. No metric exporters, no Prometheus scrape targets, no custom instrumentation. The data already exists in the tables your application writes to.

### Operational Panels (PostgreSQL data source)

- **Queue depth over time** — are tasks accumulating faster than workers process them?
- **Task completion rate** — throughput, binned by minute or hour
- **Error rate by task type** — which workflows are failing?
- **Active leases** — how much in-flight work exists right now?
- **Stuck supervisor count** — tasks that have exhausted retries and need attention

### Business Panels (PostgreSQL data source)

- User activity and registration trends
- Feature usage counts
- Workflow completion rates and conversion funnels

The same data source serves both. An operations engineer and a product manager look at different panels on the same dashboard, querying the same database.

### Log Panels (Loki data source)

- Error spikes across containers — a sudden increase in error-level logs
- Request latency distribution — parsed from structured log fields
- Container health — a container that stops producing logs is a container that's dead

---

## Why Not OpenTelemetry?

In a database-first system with a short, deterministic request chain — Caddy → Gateway → PostgREST → PostgreSQL — distributed tracing adds complexity without proportional value.

OpenTelemetry excels when requests fan out across dozens of services, any of which might be the bottleneck. That's not this architecture. The request chain is short and linear, and the database is always the terminal node. `X-Request-ID` correlation provides sufficient traceability across the handful of services that exist.

When you have a complex microservice mesh, invest in distributed tracing. When you have four stateless services and one database, invest in better SQL queries. The observability strategy should match the architecture's actual complexity — not the complexity you might have someday.

---

## Zero-Configuration Log Collection

Grafana Alloy connects to the Docker socket and auto-discovers every running container. When you deploy a new service, its logs flow to Loki automatically. No sidecar to add. No config file to update. No label mapping to maintain.

This matches the broader architectural principle: application-side complexity should be minimal. Services write structured JSON to stdout. Infrastructure handles collection, indexing, and retention. A developer adding a new service doesn't need to know anything about the observability stack — they get logs for free.
