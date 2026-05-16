# Database-First Development

A complete guide to building systems where PostgreSQL is not just storage — it's the application itself.

---

## What Is This?

This documentation teaches a way of building software where the database is the single source of truth for logic, state, and coordination. Application services become thin, stateless, and replaceable. Business rules are enforced by constraints. Workflows are orchestrated by SQL supervisors. The system is always inspectable via `SELECT`.

The principles draw from Erlang/OTP (supervision trees, let-it-crash), functional programming (immutable facts, pure decisions), and decades of PostgreSQL reliability. The result is a system with fewer moving parts, automatic crash recovery, and built-in observability.

---

## Documentation Map

### Philosophy

| Document | Description |
|----------|-------------|
| [The Manifesto](philosophy/manifesto.md) | Core thesis, seven principles, and the fundamental shift in thinking |

### Architecture

| Document | Description |
|----------|-------------|
| [System Architecture](architecture/overview.md) | Component map, data flow diagrams, infrastructure topology, and key design decisions |
| [The Gateway](architecture/gateway.md) | The thin, replaceable reverse proxy — what it does and why it has zero business logic |
| [Supervisors & Workers](architecture/workers.md) | Background processing via Facts → Logic → Effects, supervision trees, crash recovery |

### Patterns

| Document | Description |
|----------|-------------|
| [Database Patterns](patterns/database-patterns.md) | The full toolkit: schema organization, audit trails, soft deletes, append-only state, transactional outbox, lease-based queues, and more |

### Security

| Document | Description |
|----------|-------------|
| [Security Overview](security/overview.md) | In-database auth, least-privilege grants, RLS, ID generation, file encryption, secrets management, GDPR-compliant deletion |

### Observability

| Document | Description |
|----------|-------------|
| [Observability Overview](observability/overview.md) | "Observe, don't test" — database-first monitoring, structured logging, dashboards that query PostgreSQL directly |

### Guides

| Document | Description |
|----------|-------------|
| [Getting Started](guides/getting-started.md) | Step-by-step: from zero to a running database-first system with PostgREST, background jobs, and observability |

---

## Reading Order

If you're new to this approach, we recommend reading in this order:

1. **[The Manifesto](philosophy/manifesto.md)** — Understand the philosophy
2. **[System Architecture](architecture/overview.md)** — See how the pieces fit together
3. **[Getting Started](guides/getting-started.md)** — Build something hands-on
4. **[Database Patterns](patterns/database-patterns.md)** — Learn the schema patterns
5. **[Supervisors & Workers](architecture/workers.md)** — Understand background processing
6. **[The Gateway](architecture/gateway.md)** — See what a "thin service" looks like
7. **[Security](security/overview.md)** — Lock it down for production
8. **[Observability](observability/overview.md)** — Monitor with confidence

---

## Core Ideas at a Glance

| Principle | One-Liner |
|-----------|-----------|
| Database is the app | Business logic lives in PostgreSQL functions, not service layers |
| Declarative | Constraints and triggers replace procedural validation |
| Append-only facts | Never update state — derive it from recorded events |
| Supervisors | Erlang-style orchestration in SQL: facts → decide → act |
| Thin services | Gateway, worker, file service — all replaceable, all stateless |
| Observe, don't test | SQL queries and dashboards reveal truth; facts functions are your diagnostic tools |
| Transactional outbox | Jobs created atomically with business data — no phantom work |
| Crash recovery | Lease expiry + idempotent handlers = crashes are non-events |

---

## The Stack

A minimal database-first system needs:

```
PostgreSQL          → The brain (logic, state, scheduling)
PostgREST           → Protocol translator (schema → REST API)
Reverse Proxy       → TLS, routing, request correlation
Worker (optional)   → Executes external I/O dispatched by supervisors
```

Everything else — Redis, Kafka, ORMs, service meshes — is complexity you probably don't need.

---

## License

This documentation is open for learning and adaptation. The patterns described here are not proprietary — they're compositions of well-established database features applied with a specific philosophy.
