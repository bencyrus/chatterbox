## Worker

Purpose

- Background processor that leases tasks from `queues.task` and dispatches by `task_type`.

Philosophy

- Supervisors in Postgres decide what to do and when; the worker only executes.
- Keep the worker minimal and generic: lease work, invoke database handlers, and call providers. All scheduling and retries live in SQL.
- This ensures idempotency (derived from facts) and reduces coupling: swapping providers or adding processes doesn’t require worker orchestration changes.

Read next

- Lifecycle: [`./lifecycle.md`](./lifecycle.md)
- Task payloads and handlers: [`./payloads.md`](./payloads.md)
- Email processor: [`./email.md`](./email.md)
- SMS processor: [`./sms.md`](./sms.md)
- Postgres queues/worker contract: [`../postgres/queues-and-worker.md`](../postgres/queues-and-worker.md)
