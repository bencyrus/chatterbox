## Exception Handling

Status: current
Last verified: 2025-01-25

← Back to [`docs/patterns/README.md`](./README.md)

### Why this pattern

Most codebases treat exceptions as control flow: wrap everything in try/catch, log errors, and try to keep going. This creates systems that silently corrupt data, hide bugs, and fail in unpredictable ways. The alternative is to let exceptions be what they are: signals that something truly unexpected happened. Design your system to handle failure gracefully at a higher level.

### The core principle

**Exceptions should be exceptional.**

If something can reasonably happen during normal operation, it's not an exception. It's a case you should handle explicitly. Exceptions are for genuinely unexpected situations: bugs, invariant violations, and impossible states your code assumed could never occur.

When an exception happens, it means your assumptions were wrong. The correct response is usually to stop, not to patch things up and continue.

### The supervisor fence

The supervisor model from actor systems (Erlang, Elixir) provides the key insight: build a fence around your work units. Inside the fence, processes do their jobs and fail noisily when something unexpected happens. Outside the fence, supervisors decide what to do about failures.

```
┌──────────────────────────────────────────────────────────────────┐
│                           SUPERVISOR                             │
│   Decides: restart? retry? give up? escalate?                    │
│                                                                  │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│   │   Task A    │  │   Task B    │  │   Task C    │              │
│   │  (crashes)  │  │  (running)  │  │  (running)  │              │
│   └─────────────┘  └─────────────┘  └─────────────┘              │
│         ↓                                                        │
│   Supervisor restarts Task A; B and C unaffected                 │
└──────────────────────────────────────────────────────────────────┘
```

The fence provides isolation. A failure in one task doesn't corrupt others. The supervisor can restart the failed task, retry with backoff, or mark it as permanently failed. None of this affects the rest of the system.

### Fail fast, recover gracefully

There are two levels to think about:

**At the individual record/task level: fail fast.** When something unexpected happens while processing a single record, stop immediately. Don't try to patch around it. Don't guess at the right behavior. Let the exception propagate. A stopped task is safer than a task that continues in a corrupted state.

**At the system level: keep the system running.** The supervisor catches the failure, logs it, and decides what to do. Maybe retry. Maybe skip. Maybe alert a human. But the system as a whole keeps processing other records, other tasks, other work.

This is the key insight: individual records should fail fast; the system should degrade gracefully.

### Why not handle all exceptions?

Defensive programming taken to extremes creates a different problem: systems that never crash but silently produce wrong results.

Consider this pattern:

```sql
-- DANGEROUS: hiding errors
begin
    -- complex business logic
    perform do_something_important(_record_id);
exception when others then
    raise notice 'Error processing record %, continuing...', _record_id;
    -- swallow the error and continue
end;
```

This feels safe, but it's actually dangerous:

1. **You don't know what went wrong.** The `when others` clause catches everything, including bugs you didn't anticipate.
2. **The record is now in an undefined state.** Did the operation partially complete? You don't know.
3. **The error might recur forever.** Without the exception surfacing, you might never fix the underlying bug.
4. **The system appears healthy.** Monitoring shows no failures, but data is quietly being corrupted.

A system that crashes noisily when something unexpected happens is more reliable than one that silently continues in a bad state.

### What belongs in exception handlers

Handle exceptions only when you know exactly what went wrong and exactly how to fix it:

**Good: handling a specific, expected condition**

```sql
-- GOOD: specific exception, known recovery
begin
    insert into users (email)
    values (_email);
exception when unique_violation then
    -- We know exactly what happened: duplicate email
    -- We know exactly what to do: return the existing user
    select user_id
    into _user_id
    from users
    where email = _email;
end;
```

**Bad: catching everything "just in case"**

```sql
-- BAD: catching unknown errors with unknown recovery
begin
    perform complex_business_logic(_id);
exception when others then
    -- What went wrong? We don't know.
    -- What's the right recovery? We're guessing.
    perform log_error('Something failed');
    return null;
end;
```

### The economics of error handling

Error-handling code has a cost:

1. **It's rarely executed.** Bugs in error handlers go unnoticed until production.
2. **It's hard to test.** You need to simulate failure conditions.
3. **It couples your code.** Catching specific exceptions creates dependencies.
4. **It hides bugs.** Overly broad handlers mask real problems.

The "let it crash" philosophy argues that less error-handling code means fewer bugs. Code for the happy path; let failures propagate to a supervisor that knows how to handle them.

### Expected vs unexpected failures

Distinguish between:

**Expected failures** (not really exceptions):
- User provides invalid input → validate and return an error
- External API returns an error status → handle as a case in your logic
- Record not found → return null or a "not found" status

These aren't exceptions; they're normal cases your code should handle explicitly.

**Unexpected failures** (true exceptions):
- Foreign key constraint violated when your logic ensures valid references
- Division by zero when your logic ensures non-zero divisors
- Out of memory, disk full, network partition

These indicate bugs or environmental failures. Let them crash. Investigate when they happen.

### Implementing in PostgreSQL supervisors

Here's how exception propagation works in practice.

**The task handler focuses on the happy path and does not catch exceptions:**

```sql
create or replace function billing.process_invoice_handler(
    _payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
    _invoice_id bigint := (_payload->>'invoice_id')::bigint;
    _facts record;
begin
    -- Facts
    _facts := billing.process_invoice_facts(_invoice_id);

    -- Logic: invariant check
    if _facts.total <> _facts.line_items_sum then
        raise exception 'Invoice total does not match line items for invoice %', _invoice_id;
    end if;

    -- Effects
    perform billing.record_invoice_processed(_invoice_id);

    return jsonb_build_object('status', 'processed');
end;
$$;
```

If the invariant check fails, the `raise exception` throws. The task does not catch it.

**The worker catches the exception and calls the error handler:**

The worker wraps the handler call. When an exception occurs:

1. The exception exits the handler function
2. The worker catches it
3. The worker calls the `error_handler` with the error message
4. The error handler records the failure fact

```sql
-- The error handler is an effect function (called by the worker)
create or replace function billing.record_invoice_failure(
    _payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
    _invoice_id bigint := (_payload->'original_payload'->>'invoice_id')::bigint;
    _error_message text := _payload->>'error';
begin
    perform billing.append_invoice_failure(_invoice_id, _error_message);

    return jsonb_build_object('success', true);
end;
$$;
```

When the invoice handler throws `'Invoice total does not match line items for invoice 42'`:

1. The exception exits the handler function
2. The worker catches it and builds a payload with the error message
3. The worker calls `billing.record_invoice_failure` with `{"original_payload": {...}, "error": "Invoice total does not match..."}`
4. The error handler calls `billing.append_invoice_failure` to record the failure fact
5. The supervisor sees the failure on its next run and decides: retry? give up? alert?

The task never knew about failure handling. The worker provided the fence. The error is recorded as a fact that the supervisor can query.

**Why the task should not catch its own exceptions:**

```sql
-- BAD: task catches its own exceptions
create or replace function billing.process_invoice_handler(
    _payload jsonb
)
returns jsonb
language plpgsql
as $$
begin
    begin
        -- business logic that might fail
    exception when others then
        -- This hides the real error from the worker
        -- The worker thinks the task succeeded (no exception reached it)
        -- The error handler is never called
        -- The supervisor never knows to retry
        return jsonb_build_object('status', 'error', 'message', sqlerrm);
    end;
end;
$$;
```

This looks defensive but it breaks the system. The worker never sees the exception because the task swallowed it. The error handler is never called. The failure disappears into a return value that might not even be checked.

### Validation vs exceptions

Input validation is not exception handling. Validate inputs at the boundary and return explicit error responses:

```sql
-- GOOD: explicit validation, not exceptions
create or replace function api.create_user(
    _payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
    _email text := _payload->>'email';
begin
    -- Validate inputs explicitly
    if _email is null or _email = '' then
        return jsonb_build_object('error', 'email_required');
    end if;

    if not _email ~ '^.+@.+\..+$' then
        return jsonb_build_object('error', 'invalid_email_format');
    end if;

    -- Happy path continues...
end;
$$;
```

Don't use exceptions for validation:

```sql
-- BAD: using exceptions for validation
begin
    if _email is null then
        raise exception 'email required';
    end if;
exception when others then
    return jsonb_build_object('error', sqlerrm);
end;
```

### Assertions for invariants

Use `raise exception` to assert invariants, which are conditions that should never be false if your code is correct:

```sql
-- GOOD: asserting an invariant
if _facts.num_scheduled < _facts.num_failures then
    raise exception 'Invariant violation: scheduled (%) < failures (%)',
        _facts.num_scheduled, _facts.num_failures
        using hint = 'This indicates a bug in scheduling logic';
end if;
```

These aren't errors to handle; they're bugs to fix. The exception ensures you notice them.

### When things crash

When an unexpected exception occurs:

1. **The task stops immediately.** No partial effects, no corrupted state.
2. **The error is logged with full context.** Stack trace, parameters, current state.
3. **The supervisor decides what to do.** Retry? Give up? Alert?
4. **You investigate.** Because this shouldn't have happened.

This is healthier than a system that hides errors and silently degrades.

### Summary

| Situation | Response |
|-----------|----------|
| Invalid user input | Validate explicitly, return error response |
| Expected failure (API error, not found) | Handle as a case in your logic |
| Specific, recoverable condition | Catch the specific exception, apply known fix |
| Invariant violation | Assert with `raise exception`, investigate when hit |
| Unexpected failure | Let it crash, let supervisor handle |

The principle: **code for the happy path, let failures propagate to the fence, and investigate when unexpected things happen.**

### See also

- Supervisor pattern: [`./supervisors.md`](./supervisors.md)
- Facts, Logic, Effects: [`./facts-logic-effects.md`](./facts-logic-effects.md)
- Queues and worker mechanics: [`../postgres/queues-and-worker.md`](../postgres/queues-and-worker.md)
