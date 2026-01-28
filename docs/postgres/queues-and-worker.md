## Queues and Worker

Status: current
Last verified: 2025-10-08

← Back to [`docs/postgres/README.md`](./README.md)

### Why this exists

- Describe the generic queue, the worker contract, and the supervisor-driven orchestration pattern implemented in SQL.

### Core data model (queues)

- `queues.task`
  - Columns: `task_id`, `task_type` (`'db_function' | 'email' | 'sms' | 'file_delete'`), `payload jsonb`, `enqueued_at`, `scheduled_at`.
  - Immutable after creation; state is tracked via append-only tables below.
- `queues.task_lease`
  - Append-only record of task claim attempts: `task_lease_id`, `task_id`, `leased_at`, `expires_at`.
  - A task is "claimed" when it has an active lease (`expires_at > now()`).
  - If the worker crashes or fails to complete before `expires_at`, the task becomes available again.
- `queues.task_completed`
  - Terminal state: `task_id` (PK), `completed_at`.
  - Once a task is completed, it is never processed again.
- `queues.error`
  - Append-only operational error log with `task_id` and `error_message`.

### Functions

- `queues.enqueue(_task_type, _payload, _scheduled_at default now()) returns void`
  - Used by supervisors/handlers to schedule work; the worker never enqueues.
- `queues.dequeue_next_available_task() returns queues.task`
  - Selects one ready task ordered by `scheduled_at, task_id` using `for update skip locked`.
  - Task is available when: not completed AND no active lease (`expires_at > now()`).
  - Inserts a lease row with 5-minute expiry; if worker crashes, lease expires and task is retried.
- `queues.complete_task(_task_id bigint) returns void`
  - Marks a task as completed (idempotent via `on conflict do nothing`).
  - Called by the worker after successful processing.
- `queues.fail_task(_task_id bigint, _error_message text) returns void`
  - Records a task failure with error message (appends to `queues.error`).
  - Called by the worker on processing failure; does not mark task as terminal.
- `internal.run_function(function_name text, payload jsonb) returns jsonb`
  - Security invoker runner that executes named functions (supervisors/handlers). Worker has execute on this and on whitelisted business functions (security definer).

### Worker lifecycle (Go)

- **Lease**: Acquire a task via `queues.dequeue_next_available_task()` which creates a 5-minute lease.
- **Dispatch**: Route by `task_type` to the appropriate processor:
  - `db_function`: call `internal.run_function(payload.db_function, payload)` and respect the JSON envelope
  - `email`/`sms`: call `before_handler` to build a provider payload, call the provider, then call `success_handler` or `error_handler`
- **Record failure** (if error): call `queues.fail_task(task_id, message)` for observability.
- **Complete**: Always call `queues.complete_task(task_id)` after processing, whether success or failure. Retries are handled by supervisors creating new attempts, not by re-processing the same task. Lease expiry is only for crash recovery.
- Always pass the full `payload jsonb` through; DB functions extract what they need.

### Standard JSON envelope (DBFunctionResult)

```json
{
  "status": "succeeded",
  "payload": {}
}
```

- `status`: `"succeeded"` indicates success; any other value indicates a non-success outcome (e.g., `"missing_attempt_id"`, `"attempt_not_found"`, `"max_attempts_reached"`).
- `payload`: optional typed data returned by `before_handler` calls.

The worker checks `status == "succeeded"` to determine success. Non-success statuses are logged but not treated as fatal errors — supervisors use descriptive status values to communicate outcomes clearly.

### Supervisor pattern (ICO: Input → Compute → Output)

- Supervisors orchestrate business processes using append-only facts.
- Inputs: small facts functions like `has_*_succeeded_attempt(task_id)`, `count_*_failed_attempts(task_id)`, `count_*_attempts(task_id)`.
- Compute: decide whether to schedule a channel task; compute next check time (e.g., exponential backoff based on failures).
- Output: create an attempt, enqueue a channel task with handlers, and re-enqueue the supervisor.
- Termination: exit when a terminal fact exists or attempts are exhausted.

### Supervisor building blocks

For any long‑running or retriable business process, we follow a consistent pattern:

- **Tables (task, attempts, outcomes)**:
  - `foo_task`: root task row; one per logical process instance (e.g., per message, per file, per account).
  - `foo_attempt`: one row per scheduled attempt; references `foo_task`.
  - `foo_attempt_succeeded`: one row per succeeded attempt (primary-keyed by `foo_attempt_id`).
  - `foo_attempt_failed`: one row per failed attempt (primary-keyed by `foo_attempt_id`), with a free‑form `error_message`.
- **Fact helpers (Input)**:
  - `has_foo_succeeded_attempt(foo_task_id) returns boolean` — checks if any attempt succeeded (joins attempt → succeeded).
  - `count_foo_failed_attempts(foo_task_id) returns integer` — counts failed attempts (joins attempt → failed).
  - `count_foo_attempts(foo_task_id) returns integer` — counts total attempts.
  - Optional stuck detection: `is_foo_stuck(domain_id) returns boolean` that caps retries.
- **Supervisor (Compute + Output)**:
  - Security‑definer PL/pgSQL function `domain.foo_supervisor(_payload jsonb) → jsonb`.
  - Validates IDs from `_payload`.
  - Locks the root `foo_task` row (`for update`) to serialize concurrent runs.
  - Reads facts via helpers, computes retry/backoff windows, and decides whether to:
    - Create an attempt and enqueue a worker task (email/sms/file_delete/db_function) with the attempt ID.
    - Record a failure and stop (when stuck or max attempts reached).
    - Return success status when done.
  - Always re‑enqueues itself as a `db_function` task until it reaches a terminal condition.

### Email example (current implementation)

- Tables: `comms.send_email_task`, `comms.send_email_attempt`, `comms.send_email_attempt_succeeded`, `comms.send_email_attempt_failed`.
- Supervisor: `comms.send_email_supervisor(_payload jsonb)`
  - Validates `send_email_task_id`, locks the root row, checks success/failure counts via facts functions.
  - If no outstanding attempt (`num_attempts = num_failures`), creates an attempt and enqueues an `email` task with the attempt ID and handlers:
    - `before_handler`: `comms.get_email_payload` (receives `send_email_attempt_id`)
    - `success_handler`: `comms.record_email_success` (records against attempt)
    - `error_handler`: `comms.record_email_failure` (records against attempt)
  - Re-enqueues itself based on exponential backoff from failures.

The SMS flow mirrors this pattern (`comms.send_sms_task`, `comms.send_sms_attempt`, `comms.send_sms_supervisor`, and corresponding handlers).

### Handler contracts (before / success / error)

Handlers are plain SQL functions that encapsulate **Input → Compute → Output** for a specific step:

- **Before handler**: `before_handler(payload jsonb) → jsonb`
  - Called *before* talking to an external provider.
  - Receives the original task payload.
  - Returns a `DBFunctionResult` JSON envelope:
    - `success: true|false`
    - `error: string` (unexpected failures)
    - `validation_failure_message: string` (non‑retriable issues)
    - `payload: json` (provider‑specific payload; e.g. `{ "to_address": "...", ... }`).
  - The worker unmarshals `payload` into a typed struct and passes it to the provider.
- **Success handler**: `success_handler(payload jsonb) → jsonb`
  - Called only when the worker’s provider call succeeds.
  - Receives a JSON body with:
    - `original_payload`: the original task payload.
    - `worker_payload`: arbitrary JSON from the provider/service.
  - Responsible for writing **success facts** against the attempt (e.g. `..._attempt_succeeded`) and any follow‑up side‑effects.
  - Must be **idempotent** (`on conflict do nothing` where appropriate).
- **Error handler**: `error_handler(payload jsonb) → jsonb`
  - Called when the worker fails processing a task.
  - Receives:
    - `original_payload`: the original task payload.
    - `error`: a stringified error message from the worker.
  - Responsible for writing **failure facts** against the attempt (e.g. `..._attempt_failed`) and any observability fields.

The worker never interprets domain‑specific fields; it only understands:

- `task_type`, `db_function`, `before_handler`, `success_handler`, `error_handler`,
- plus the standard `DBFunctionResult` and handler payload shapes defined in `worker/internal/types`.

### Payload contracts (examples)

Supervisor task payload

```json
{
  "task_type": "db_function",
  "db_function": "comms.send_email_supervisor",
  "send_email_task_id": 123
}
```

Channel task payload (email)

```json
{
  "task_type": "email",
  "send_email_attempt_id": 456,
  "before_handler": "comms.get_email_payload",
  "success_handler": "comms.record_email_success",
  "error_handler": "comms.record_email_failure"
}
```

Channel task payload (file_delete)

```json
{
  "task_type": "file_delete",
  "file_deletion_task_id": 42,
  "file_id": 987,
  "before_handler": "files.get_file_delete_payload",
  "success_handler": "files.record_file_delete_success",
  "error_handler": "files.record_file_delete_failure"
}
```

In the file deletion flow:

- The **supervisor** (`files.file_deletion_supervisor`) owns retries, backoff, and termination.
- The **before handler** resolves the current file row (`bucket`, `object_key`, etc.) from `file_id`.
- The worker calls the files HTTP service to obtain a signed GCS `DELETE` URL and then deletes the object from storage.
- The **success handler** records success facts (and, via helper functions, marks the file logically deleted).
- The **error handler** records failure facts used by `files.is_file_deletion_stuck`.

### Security and grants

- Worker role: `worker_service_user`
  - Grants: usage on `queues`, `internal`, and business schemas; execute on `queues.dequeue_next_available_task`, `queues.complete_task`, `queues.fail_task`, `internal.run_function`, and specific business functions it must call (supervisors/handlers).
- Business functions (supervisors/handlers): `security definer` with targeted `execute` grants to `worker_service_user`.
- Function runner: `security invoker`; no direct table grants to the worker.

See comprehensive guidance in [Security and Grants](security.md) for revoke/grant patterns and role boundaries. This section focuses on the worker-specific permissions above.

### Operational notes

- Dequeue and processing are separate transactions to avoid infinite retry loops on failure.
- Use `for update skip locked` to prevent duplicate processing.
- Supervisors/handlers perform all scheduling; the worker never enqueues tasks by itself.
- **Crash recovery vs business retries**: Lease expiry handles crash recovery only (worker dies mid-processing). Business-level retries (e.g., email send failed) are handled by supervisors creating new attempts with new tasks. The worker always calls `complete_task` after processing, whether success or failure.
- **Crash resilience**: If a worker crashes mid-processing, the lease expires (default 5 minutes) and the task becomes available again. Handlers are idempotent (`ON CONFLICT DO NOTHING`), so re-running after a crash is safe.
- **Audit trail**: The `task_lease` table records every claim attempt, useful for debugging tasks that were retried due to crashes.

### Implementing a new supervisor-driven business process

When adding a new background process (e.g., “send reminder”, “rebuild summary”, “purge data”), follow this recipe:

1. **Model the root task and attempts**
   - Create tables:
     - `domain.foo_task (foo_task_id bigserial primary key, <foreign keys>, created_at timestamptz default now())`.
     - `domain.foo_attempt (foo_attempt_id bigserial primary key, foo_task_id bigint not null references domain.foo_task, created_at timestamptz default now())`.
     - `domain.foo_attempt_succeeded (foo_attempt_id bigint primary key references domain.foo_attempt, created_at timestamptz default now())`.
     - `domain.foo_attempt_failed (foo_attempt_id bigint primary key references domain.foo_attempt, error_message text, created_at timestamptz default now())`.
   - Add helpers:
     - `has_foo_succeeded_attempt(foo_task_id)` — joins attempt → succeeded.
     - `count_foo_failed_attempts(foo_task_id)` — joins attempt → failed.
     - `count_foo_attempts(foo_task_id)`.
     - Optional `is_foo_stuck(domain_id)` when the process can become permanently blocked.

2. **Add an idempotent kickoff function**
   - `domain.kickoff_foo(<ids>, _scheduled_at timestamptz default now(), out validation_failure_message text)`.
   - Responsibilities:
     - Validate required IDs and existence of referenced rows.
     - Return a human‑readable `validation_failure_message` instead of raising for invalid input.
     - If a `foo_task` already exists for the same logical root (e.g., `account_id`), **do nothing** (supervisor is already running).
     - Otherwise, insert a `foo_task` row and enqueue the supervisor as a `db_function` task via `queues.enqueue`.

3. **Decide on channel shape**
   - If the work is **pure SQL** (no external provider), you can keep everything as `task_type = 'db_function'` and have the supervisor call subordinate SQL functions directly.
   - If the work involves an **external provider** or long‑running side effects (email, SMS, storage, etc.):
     - Introduce or reuse a channel `task_type` (`'email'`, `'sms'`, `'file_delete'`, or a new one).
     - Define the worker‑side payload struct in Go under `worker/internal/types` (if needed).
     - Decide what belongs in:
       - the **original task payload** (IDs, handler names),
       - the **before handler payload** (fully prepared provider request),
       - the **success/error handler payloads** (facts and bookkeeping only).

4. **Implement the supervisor**
   - Follow the ICO pattern:
     - **Input**:
       - Validate IDs from `_payload`.
       - Lock the root `foo_task` row.
       - Read facts: `has_foo_succeeded_attempt`, `count_foo_failed_attempts`, `count_foo_attempts`.
     - **Compute**:
       - If succeeded → return.
       - If failures ≥ `max_attempts` → record a final failure (optional) and return.
       - Compute `_next_check_at` using exponential backoff on failures.
     - **Output**:
       - If there is **no outstanding attempt** (`num_attempts = num_failures`):
         - Insert a `foo_attempt` row and capture the attempt ID.
         - Enqueue the channel task (or subordinate `db_function`) with the attempt ID and handlers.
       - Always enqueue the supervisor again at `_next_check_at`.

5. **Design handlers (if using a non-`db_function` channel)**
   - **Before handler**:
     - Receives the attempt ID in the payload.
     - Resolves domain records into a provider payload (e.g., look up `email_message` by joining attempt → task → message).
     - Returns a `DBFunctionResult` with a `payload` that matches the worker’s typed struct.
   - **Success handler**:
     - Receives the attempt ID via `original_payload`.
     - Records success facts against the attempt (`foo_attempt_succeeded`) and any terminal flags.
     - Must be idempotent (`on conflict do nothing`).
   - **Error handler**:
     - Receives the attempt ID via `original_payload`.
     - Records failure facts against the attempt (`foo_attempt_failed`) with the error message.
     - Must be idempotent and never raise on normal failures.

6. **Wire grants and worker support**
   - Mark all supervisors and handlers as `security definer` and grant execute to `worker_service_user` only.
   - In the worker:
     - Register a processor for the new `task_type` (or reuse an existing processor such as `db_function` / `email` / `sms` / `file_delete`).
     - Ensure the processor uses `HandlerInvoker` where appropriate to call the before/success/error handlers.

7. **Test the flow end‑to‑end**
   - From SQL:
     - Seed minimal domain data.
     - Call the `kickoff_*` function and verify that:
       - `*_task` is created.
       - A supervisor `db_function` task is enqueued.
   - From the worker:
     - Run the worker against a dev database.
     - Observe:
       - Channel tasks being enqueued and processed.
       - `*_attempt`, `*_attempt_failed`, `*_attempt_succeeded` facts updating as expected.
       - Stuck conditions (if any) being detected and terminating retries after `max_attempts`.

### Example checklist: account and file deletion supervisors

Use this as a concrete sanity check for the account deletion stack:

- **Happy path**
  - Create an account, profile, cue, upload intent, and complete at least one recording upload so that `learning.profile_cue_recording` and `files.file` have rows tied to the account.
  - Call `api.request_account_deletion(_account_id)` and ensure:
    - `accounts.account_flag` contains `'deleted'` for the account.
    - `accounts.account_deletion_task` has one row for the account.
  - Run the worker (or manually invoke supervisors in order) until:
    - Each file for the account has a `files.file_deletion_task` row, a corresponding `..._succeeded` row, and `files.file_metadata` contains `"deleted": true` via `files.mark_file_deleted`.
    - `accounts.account_anonymization_task` gets created and `accounts.account_flag` contains `'anonymized'`.
    - `accounts.account_deletion_task_succeeded` has a row for the task.
- **File deletion stuck path**
  - Arrange for `file_delete` tasks to fail (e.g., point storage at an invalid bucket in a dev environment) so that `files.record_file_delete_failure` is called multiple times.
  - Confirm that:
    - `files.file_deletion_task_failed` accumulates failures.
    - `files.is_file_deletion_stuck(file_id)` returns `true` after the configured max attempts.
    - `accounts.account_deletion_task_failed` receives a row with an appropriate error message and the supervisor stops retrying.
- **Account anonymization stuck path**
  - Simulate failures in `accounts.anonymize_account` (e.g., by temporary raise in a dev branch) and observe:
    - `accounts.account_anonymization_task_failed` accumulating failures.
    - `accounts.is_account_anonymization_stuck(account_id)` returning `true` after the configured max attempts.
    - `accounts.account_deletion_task_failed` being populated and the root supervisor terminating further retries.

### See also

- Back to Postgres: [Postgres Index](README.md)
- Worker details: [Worker Docs](../worker/README.md)
