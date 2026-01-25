## Patterns

Status: current
Last verified: 2025-01-25

← Back to [`docs/README.md`](../README.md)

### Why this exists

This section documents the core design patterns used throughout Chatterbox. Each pattern is a self-contained guide that explains both the philosophy (why) and the implementation (how).

### Patterns

- [Facts, Logic, Effects](./facts-logic-effects.md) – Separating data gathering, decision making, and side effects for debuggable, testable business logic
- [Supervisors](./supervisors.md) – Orchestrating workflows with small, safe steps that are easy to debug and retry
- [Exception Handling](./exception-handling.md) – Let exceptions be exceptional; fail fast at the task level, recover gracefully at the system level

### Reading order

If you're new to the codebase:

1. Start with **Facts, Logic, Effects** – this pattern is foundational and used everywhere
2. Then read **Supervisors** – builds on FLE and explains how we orchestrate workflows
3. Then read **Exception Handling** – explains the philosophy behind how we handle failures

### See also

- SQL formatting conventions: [`../postgres/sql-style-guide.md`](../postgres/sql-style-guide.md)
- Queues and worker mechanics: [`../postgres/queues-and-worker.md`](../postgres/queues-and-worker.md)
- Postgres architecture: [`../postgres/README.md`](../postgres/README.md)
