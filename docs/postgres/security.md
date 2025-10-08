## Security and Grants

Status: current
Last verified: 2025-10-08

← Back to [`docs/postgres/README.md`](./README.md)

### Why this exists

- Centralize guidance on roles, privileges, `security definer`/`security invoker`, and safe grants across schemas.

### Principles

- Prefer least privilege and explicit per-function grants.
- Revoke broad `public` execute on internal schemas; grant narrowly to service roles.
- Keep business functions (supervisors/handlers) as `security definer` with targeted `execute` to the worker role.
- Keep the function runner as `security invoker` and avoid direct table grants to the worker.
- Limit PostgREST-facing roles to `api` schema only.

### Roles and boundaries

- Application roles via PostgREST: `anon`, `authenticated` (limited to `api` views and functions).
- Connection role: `authenticator` (switches into `anon`/`authenticated`).
- Worker role: `worker_service_user` (minimal grants to dequeue tasks and call allowed business functions).

### Recommended revokes and grants (example)

```sql
-- revoke broad function execute; prefer explicit, per-role grants
revoke execute on all functions in schema internal from public;
revoke execute on all functions in schema queues from public;
revoke execute on all functions in schema comms from public;

-- worker role gets only what it needs
grant usage on schema queues, internal, comms to worker_service_user;
grant execute on function queues.dequeue_next_available_task() to worker_service_user;
grant execute on function queues.append_error(bigint, text) to worker_service_user;
grant execute on function internal.run_function(text, jsonb) to worker_service_user;
-- supervisors/handlers are security definer; grant execute individually:
grant execute on function comms.send_email_supervisor(jsonb) to worker_service_user;
grant execute on function comms.get_email_payload(jsonb) to worker_service_user;
grant execute on function comms.record_email_success(jsonb) to worker_service_user;
grant execute on function comms.record_email_failure(jsonb) to worker_service_user;

-- postgrest roles get execute only on public API functions in schema api
grant usage on schema api to anon, authenticated;
grant execute on all functions in schema api to anon, authenticated;
```

### Notes

- Favor targeted grants per function rather than schema-wide executes for internal schemas.
- Keep internal-only helpers outside `api` and avoid exposing them via PostgREST.

### See also

- Back to Postgres: [Postgres Index](README.md)
- Queues/worker contract: [Queues and Worker](queues-and-worker.md)
