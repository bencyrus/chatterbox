# The Manifesto

What if your database wasn't just storage — but your entire application?

Most teams treat their database as a dumb bucket. Data goes in, data comes out. The real work happens somewhere else — in service layers, in microservices, in orchestration platforms that cost more to operate than the business logic they contain.

We think that's backwards.

---

## Core Thesis

**The database is the application.** PostgreSQL is not a persistence layer you hide behind an ORM. It's a live system — the primary artifact where business logic, state machines, scheduling, authentication, and workflow orchestration all reside.

Application processes become thin, stateless, and replaceable. They exist to handle I/O that the database can't reach: sending emails, calling APIs, rendering templates. Everything else — the rules, the state, the truth of your system — lives in the database.

> The goal is not to write SQL instead of Python. The goal is to move authority to the place that already guarantees consistency: the database itself.

---

## The Seven Principles

### 1. The Database is the System of Record

Business rules, constraints, audit trails, and state machines live in PostgreSQL. Application processes are stateless and replaceable.

When you express a rule like "an order cannot transition from `shipped` to `draft`" as a CHECK constraint or a trigger, that rule is enforced universally — regardless of which service, script, or admin tool touches the data. No service can bypass it. No developer can forget it.

### 2. Declarative Over Imperative

Schema declarations, constraints, and triggers replace procedural validation code. You declare what's true; the database enforces it.

Instead of writing validation functions that scatter business rules across a codebase, you declare invariants once in the schema. `NOT NULL`, `CHECK`, `EXCLUDE`, foreign keys — these aren't just data hygiene. They're your business logic, expressed in a form that cannot be circumvented.

### 3. Everything Leaves a Trail

Append-only facts. Soft deletes. Event histories. No data is ever truly lost.

State is derived from recorded facts, never stored as mutable values you hope stay consistent. When you need to know what happened, you query the record. When you need to rebuild state, you replay the facts. The audit trail isn't a feature you bolt on later — it's how the system works.

### 4. Resilience Through Data

The database is the single source of truth. When processes crash, they resume by re-reading facts. No special recovery code needed.

A supervisor process doesn't need checkpointing, journaling, or complex recovery logic. It starts up, queries the database for current state, and picks up where things left off. The database already survived the crash. Your process just needs to ask it what's true.

### 5. Simplicity Through Reduction

No Redis. No Kafka. No separate event bus. PostgreSQL handles queuing (`SKIP LOCKED`), pub/sub (`LISTEN/NOTIFY`), scheduling (temporal queries), and business logic in one place.

Fewer moving parts means fewer failure modes. Every additional system in your architecture is a new consistency boundary, a new deployment target, a new thing that can fail at 3 AM. Before adding infrastructure, ask: can PostgreSQL already do this?

### 6. Health and Clarity

If you can query it, you can understand it. The state of the system is always inspectable via SQL.

Debugging is `SELECT`, not distributed tracing across 10 services. When something goes wrong, you open a SQL console and ask the database what happened. No log aggregation pipelines. No correlation IDs threading through microservices. Just data, right there, queryable.

### 7. Business Logic as Data

State machines, workflow transitions, and validation rules are expressed as database constraints and functions. The logic lives next to the data it operates on.

When your state machine is a table with valid transitions defined as rows, anyone can understand it. When your workflow rules are functions in the same schema as the data they govern, there's no translation layer between "what the system does" and "what the data says."

---

## The Fundamental Shift

**The traditional approach:**

```
ORM Models → Service Layer → Controllers → HTTP Framework → Database (dumb storage)
```

Authority lives in application code. The database is an afterthought — a place you reluctantly put data because it has to go somewhere. Business rules scatter across models, services, and middleware. The database schema is a shadow of the real logic.

**The database-first approach:**

```
Schema → Functions → Auto-exposed API (PostgREST) → Thin Proxy
```

Authority lives in the database. The schema *is* the application. Functions encode business logic. An API layer auto-generates from the schema. Application code only exists for the things a database genuinely can't do: talk to external services, render UIs, handle file uploads.

The difference isn't cosmetic. It's a fundamental inversion of where truth lives.

---

## What This Is NOT

**Not about PostgreSQL specifically.** The principles apply to any system capable enough to be trusted with authority. Erlang, Elixir, Clojure, and Common Lisp communities have arrived at similar philosophies — building against a live, observable system rather than layering abstractions until the running system is unknowable.

**Not about avoiding all application code.** Thin services still exist. You still write code for I/O, for UX, for integrations. But that code is a *client* of the database, not the *owner* of business logic.

**Not about database vendor lock-in.** The principles — declarative rules, append-only facts, derived state, inspectability — apply to any capable RDBMS. PostgreSQL happens to be the most practical choice today, but the philosophy transcends any single product.

---

## Who This Is For

This approach is for high-trust teams who value:

- **Clarity over abstraction** — you'd rather read a schema than a class hierarchy
- **Observability over testing** — if the system is always inspectable, you catch problems in production before they become incidents
- **Simplicity over scalability theater** — you'd rather serve 10,000 users reliably from one PostgreSQL instance than serve 100 users from a Kubernetes cluster you can't debug

If your team is small, if your problem domain is complex, and if you're tired of fighting your own infrastructure — this is for you.

---

## The Payoff

When you commit to database-first development, things get remarkably simple:

- **Debugging** becomes `SELECT * FROM facts WHERE entity_id = ?` instead of hunting through distributed logs across a dozen services
- **Deployment** becomes altering a function, not orchestrating a pipeline across containers
- **Recovery** is automatic — supervisors start up, query current state, and resume work without special recovery code
- **Observability** is built-in — if you can query it, you can understand it, and you can alert on it
- **Onboarding** accelerates — new engineers read the schema and understand the system, because the schema *is* the system

The result is software that is smaller, more reliable, and more understandable than the alternative. Not because you wrote less code — but because you put authority in the right place.

---

> "This isn't about Postgres specifically. People have done similar things in Erlang, Elixir, Clojure, and Common Lisp. The value comes from building against a live, observable system — one where the truth is always queryable, the state is always inspectable, and the complexity lives where it can be reasoned about."
