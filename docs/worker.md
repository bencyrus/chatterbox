### Worker and Supervisor Design

This document describes the internal queues/worker system, the supervisor orchestration pattern, payload contracts, scheduling/backoff, and security conventions used in this project.

## Concepts

- **task**: a unit of work scheduled to run at or after `scheduled_at`. Stored as a row in `queues.task` with a `task_type` and `payload jsonb`.
- **task_type**: enumerated via `queues.task_type` domain. Current values: `db_function`, `email`, `sms`.
- **payload**: full jsonb blob passed through the system. Functions extract what they need; passing extra fields is fine.
- **handlers**: optional internal db functions referenced by name in the payload for business tasks: `before_handler`, `success_handler`, `error_handler`.
- **supervisor**: a db function that orchestrates a business process using facts. It enqueues child tasks, decides if/when to re-enqueue itself, and terminates when a terminal fact exists or limits are reached.
- **facts (append-only)**: internal business process tables are append-only. Derive state from the latest facts; avoid updates/deletes. Enforce uniqueness to guarantee at-most-once per logical event.
- **business process**: an orchestrated domain workflow (e.g., send email/sms) managed by a supervisor function. It records progress via append-only facts, enqueues child tasks (e.g., email, sms, itself), and terminates when a terminal fact exists or retry/run limits are met. Code remains idempotent and stateless; all state lives in the db and retrieved using facts functions. Kickoff typically inserts a new `queues.task` record to enqueue the supervisor.
- **function runner**: a thin wrapper that accepts a function name and a jsonb payload and invokes the target internal function. The runner is security invoker; target business functions are security definer with explicit per-function grants to the worker role.

## Worker database user and permissions

- The worker connects using a dedicated database role (for example, `worker_service_user`) with minimal privileges.
- Grants should be narrowly scoped:
  - usage on required schemas (e.g., `queues`)
  - execute on `queues.dequeue_next_available_task`
  - execute on `internal.run_function(function_name text, payload jsonb) returns jsonb` (security invoker)
  - execute on allowed business functions individually (security definer) such as supervisors and handlers
- Avoid direct table privileges; the worker interacts via `queues` functions and the business functions only.

### Function runner (pattern)

Shape of the security-invoker runner that dispatches calls (relies on per-function grants):

```sql
-- internal.run_function(function_name text, payload jsonb) returns jsonb
-- security invoker; executes target and returns jsonb; authorization via per-function grants
```

## Data model (internal)

- `queues.task`: unit of work with `task_id`, `task_type`, `payload jsonb`, timestamps `enqueued_at`, `scheduled_at`, optional `dequeued_at`.
- `queues.error`: append-only record of worker/handler errors for observability.
- `comms.message`: base comms record with `channel in ('email','sms')`.
- `comms.email_message`, `comms.sms_message`: channel-specific payload data.
- `comms.send_email_task`, `comms.send_sms_task`: root tasks per logical send.
- `comms.send_email_task_scheduled/succeeded/failed`, `comms.send_sms_task_scheduled/succeeded/failed`: facts that track scheduling and outcomes.
- Facts tables per process (email/sms):
  - `..._scheduled`: append-only; one row per attempt the supervisor schedules.
  - `..._failed`: append-only; one row per failed attempt.
  - `..._succeeded`: terminal fact; at-most-one per process task.

Permissions summary:

- Worker role (e.g., `worker_service_user`) gets:
  - usage on `queues`, `internal`, and relevant business schemas (e.g., `comms`)
  - execute on `queues.dequeue_next_available_task()`
  - execute on `internal.run_function(text, jsonb)`
  - execute on specific business functions it must call (supervisors and handlers), which are security definer

### Retry derivation (ICO: input, compute, output)

- Prefer small facts functions (input) over inline queries and avoid relying on `queues.task` for decision counts.
- Example facts functions for email:
  - `comms.has_send_email_task_succeeded(send_email_task_id) returns boolean`
  - `comms.count_send_email_task_failures(send_email_task_id) returns integer`
  - `comms.count_send_email_task_scheduled(send_email_task_id) returns integer`
- Compute stage uses these facts with a local `_max_attempts` to decide whether to enqueue the channel task and/or the supervisor. Output stage enqueues accordingly.

## Payload contracts

Supervisor task payload (db function) — prefer a single resource identifier:

```json
{
  "task_type": "db_function",
  "db_function": "comms.send_email_supervisor",
  "send_email_task_id": 123
}
```

Business task payloads (email, sms, etc.) — also reference the same single id:

```json
{
  "task_type": "email",
  "send_email_task_id": 123,
  "before_handler": "comms.get_email_payload",
  "success_handler": "comms.record_email_success",
  "error_handler": "comms.record_email_failure"
}
```

### Standard function result envelope (DBFunctionResult)

All internal functions invoked by the worker (supervisors and handlers) return a standardized JSON envelope, mapped in Go to `types.DBFunctionResult`:

```json
{
  "success": true,
  "error": "", // optional: reserved for operational failures
  "validation_failure_message": "", // optional: for non-retriable business validation failures
  "payload": {} // optional: for returning typed data to the worker
}
```

- **success**: true for successful execution.
- **error**: set by the callee only for unexpected operational errors that should be logged and typically retried by scheduling logic.
- **validation_failure_message**: set when inputs are invalid or a terminal guard is hit; the worker treats this as non-fatal and does not retry the handler.
- **payload**: optional data returned by before-handlers for provider calls (e.g., email/sms payloads).

Before-handlers MUST populate either `success: true` with a `payload`, or `success: false` with a `validation_failure_message`. Avoid using `error` for validation scenarios.

## Worker lifecycle (high-level)

Pseudo-code for the Go worker loop that processes available tasks:

```pseudo
loop forever:
  task := fetch_next_ready_task()  // select ... for update skip locked where scheduled_at <= now()
  if task is none:
    sleep(backoff)
    continue

  switch task.task_type:
    case 'db_function':
      result := run_function(task.payload.db_function, task.payload)
      if result.validation_failure_message is not null:
        record queues.error

    case 'email':
      provider_payload := null
      if task.before_handler:
        provider_payload := run_function(task.before_handler, task.payload)
      provider_result, err := send_email(provider_payload)
      if err == nil:
        if task.success_handler: run_function(task.success_handler, {original_payload: task.payload, worker_payload: provider_result})
      else:
        record queues.error
        if task.error_handler: run_function(task.error_handler, {original_payload: task.payload, error: error})

    case 'sms':
      provider_payload := null
      if task.before_handler:
        provider_payload := run_function(task.before_handler, task.payload)
      provider_result, err := send_sms(provider_payload)
      if err == nil:
        if task.success_handler: run_function(task.success_handler, {original_payload: task.payload, worker_payload: provider_result})
      else:
        record queues.error
        if task.error_handler: run_function(task.error_handler, {original_payload: task.payload, error: error})
```

Notes:

- Pass the entire `payload` to db functions and handlers; they extract what they need.
- Keep dequeuing and processing in separate transactions to avoid infinite retry loops on failure.
- Use `select ... for update skip locked` semantics to prevent duplicate processing under concurrency.
- The worker never enqueues tasks; supervisors/handlers (in db) perform scheduling and re-enqueueing as needed.

## Supervisor orchestration (email example)

```pseudo
-- comms.send_email_supervisor(payload jsonb)
-- payload: { send_email_task_id }

facts := read_current_facts_for(payload.send_email_task_id)

# 1) terminate if terminal
if success_fact exists for payload.send_email_task_id:
  return
if failure_fact exists for payload.send_email_task_id and not retries_remaining(facts):
  return

# 2) input: read facts
has_success := comms.has_send_email_task_succeeded(X)
num_failures := comms.count_send_email_task_failures(X)
max_attempts := 2  # one retry

# 3) compute + output
num_scheduled := count_scheduled(X)

if not has_success and num_failures < max_attempts:
  if num_scheduled <= num_failures:
    # no outstanding attempt; schedule a new one
    insert scheduled fact
    enqueue queues.task email now with handlers
  else:
    # an attempt is already scheduled; do not double-schedule
    (no-op)

# 4) schedule supervisor again
enqueue supervisor again after small delay if not terminal (always re-enqueued once per run)

return
```

## Scheduling and backoff

- Supervisors choose the next check time based on process-specific rules (for example: small delay after first enqueue, a polling interval while awaiting provider result, or a precise future time for scheduled sends).
- Only supervisors enqueue work; the worker never enqueues tasks.

## Operational guidance

- **Idempotency**: Supervisors must be safe to re-run; guards rely on facts and uniqueness constraints.
- **Observability**: Use `queues.error` for handler failures; add metrics/logging in the worker.
- **Throughput**: Use multiple worker goroutines with contention guarded by `skip locked`.
- Worker operational errors are appended to `queues.error` and do not abort the process beyond the current task.

## Checklist: implementing a new business process

1. Model data and facts
   - Add base record(s) and a root task table (e.g., `myprocess_task`)
   - Add terminal facts tables: `myprocess_task_succeeded`, `myprocess_task_failed`
   - Create facts helpers: `has_myprocess_task_succeeded(id)`, `count_myprocess_task_failures(id)`
2. Write handlers
   - `get_*_payload(payload jsonb) returns jsonb` (security definer)
   - `record_*_success(payload jsonb) returns jsonb` (security definer)
   - `record_*_failure(payload jsonb) returns jsonb` (security definer)
3. Write the supervisor
   - `myprocess_supervisor(payload jsonb) returns jsonb` (security definer)
   - Read facts, decide on enqueue, re-enqueue self with backoff, exit when terminal
4. Kickoff function
   - `kickoff_myprocess_task(root_id, scheduled_at timestamptz)` inserts root task and enqueues supervisor
5. Grants
   - Grant `execute` on supervisor and handlers to the worker role
6. Test end-to-end
   - Manually insert data, kickoff, run worker, verify facts and backoff
7. Observability
   - Ensure error messages are informative and carry context (ids)

## Notes

- Ensure grants are scoped to service roles; avoid broad `public` execute on internal functions.
- Security variation: For finer granularity, keep `internal.run_function` as security invoker and grant execute only on specific business functions (security definer) to `worker_service_user`.
- For certain tasks, you can run work fully in the worker and let the frontend poll for results via a controlled polling endpoint or long-lived connection.

## Example Flow: Send Email Task

This is a concrete, step-by-step story of a single email being sent with Resend as the provider. The process allows one retry.

1. Kickoff

- App creates an email message and a `send_email_task` with id X.
- A supervisor task is enqueued with payload `{ task_type: 'db_function', db_function: 'comms.send_email_supervisor', send_email_task_id: X }`.

2. Supervisor run #1

- Worker takes on the supervisor task and invokes the function.
- Supervisor reads facts for X: no success, no failure.
- Supervisor records a scheduled fact and enqueues one email task now with handlers `{ before_handler: 'comms.get_email_payload', success_handler: 'comms.record_email_success', error_handler: 'comms.record_email_failure' }`.
- Supervisor also enqueues itself to run again in a few seconds.

3. Email attempt #1 (failure)

- Worker takes the email task.
- Worker runs the before handler to build the provider payload and calls Resend.
- Provider call fails; worker appends `queues.error` and calls the error handler, which records a failure fact for X.

4. Supervisor run #2

- Worker takes the supervisor task again.
- Supervisor reads facts for X: failure exists, retry still allowed. If scheduled count equals failures, it records a new scheduled fact and enqueues a second email task now with the same handlers. If scheduled > failures (an attempt is already pending), it does not double-schedule.
- Supervisor enqueues itself to run again shortly.

5. Email attempt #2 (success)

- Worker takes the second email task.
- Worker runs the before handler and calls Resend.
- Provider call succeeds; worker calls the success handler, which records a success fact for X.

6. Supervisor run #3 (terminal)

- Worker takes the supervisor task.
- Supervisor reads facts for X: success fact exists.
- Supervisor terminates; no further tasks are enqueued.
