## Supervisors

Status: current
Last verified: 2025-01-25

← Back to [`docs/patterns/README.md`](./README.md)

### Why supervisors

We use supervisors because real systems spend most of their time waiting: on networks, providers, users, or other events. The question is not whether we wait, but where we absorb that waiting and how we keep the system understandable while we do.

### The real trade-off: where to put variability

Long, synchronous requests push all variability to the edge. That looks simple until load rises: threads block, connections pile up, and a single slow dependency ripples through the system. Supervisors move the variability inside the system as short, independent steps. Each step does a small read-think-write and then gets out of the way. The total work is the same at low volume, but under load the behavior is radically different: small steps queue and drain predictably instead of amplifying contention.

### Why small steps feel safer

Small steps are easy to reason about: they fetch current facts, make one decision, append one fact, and stop. When something fails, we haven't tangled side effects inside a long transaction; instead, we have a clear record of what happened up to that point. We can re-run a step because the next decision is derived from the facts we've already recorded. That makes timing issues, out-of-order arrivals, and retries tolerable rather than frightening.

### Why put the brain in the database

Business state lives in the database. Keeping supervision logic next to that state means decisions are made with the freshest facts and the fewest moving parts. We don't need to pass around snapshots or keep long-lived in-memory flows. The database becomes both the source of truth and the logbook of how we got there.

### The thing we're avoiding: big unsupervised work

Big queries and unsupervised batch jobs can be fine, until they aren't. Data grows, inputs shift, and a once-innocent job suddenly locks a table or blows through memory. Breaking work into supervised steps keeps the same intent but removes the blast radius. Each step is bounded in scope and time; if one spikes, it spikes alone.

### Running while we sleep

There's a difference between pushing a button while watching graphs and setting something loose at 2 a.m. Supervisors give unattended work a steady hand: a place to decide what's next, when to try again, and when to stop. The history is in the facts; the operating room is calm even if the world outside is messy.

---

## Implementing supervisors in PostgreSQL

Supervisors orchestrate workflows by checking current state and deciding the next step. This section explains how to structure supervisor functions using the facts-logic-effects pattern so they remain debuggable, testable, and maintainable.

### The ideal supervisor structure

A well-designed supervisor should be so simple that you can read it and immediately understand the business logic. No hunting through SQL queries to figure out what data is being checked.

```sql
create or replace function comms.send_email_supervisor(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _task_id bigint := (payload->>'send_email_task_id')::bigint;
    _facts record;
    _max_attempts integer := 2;
begin
    -- 1. VALIDATION
    if _task_id is null then
        return jsonb_build_object('error', 'missing_task_id');
    end if;

    -- 2. LOCK (prevent concurrent runs from double-scheduling)
    perform 1
    from comms.send_email_task t
    where t.send_email_task_id = _task_id
    for update;

    -- 3. FACTS
    _facts := comms.send_email_supervisor_facts(_task_id);

    -- 4. LOGIC + EFFECTS
    -- Terminal: already succeeded
    if _facts.has_success then
        return jsonb_build_object('status', 'succeeded');
    end if;

    -- Terminal: exhausted retries
    if _facts.num_failures >= _max_attempts then
        return jsonb_build_object('status', 'max_attempts_reached');
    end if;

    -- Schedule new attempt if none outstanding
    if _facts.num_scheduled = _facts.num_failures then
        perform comms.schedule_email_attempt(_task_id);
    end if;

    -- Always re-enqueue supervisor for next check
    perform comms.schedule_supervisor_recheck(_task_id, _facts.num_failures);

    return jsonb_build_object('status', 'scheduled');
end;
$$;
```

### Why supervisors benefit most from facts-logic-effects

Supervisors are the functions you'll debug most often. They handle retries, timeouts, race conditions, and edge cases. When something goes wrong at 2 a.m., you need to answer: "What did the supervisor see? Why did it make that decision?"

With the facts function pattern:

1. **Reproduce the exact state**: Call `schema.supervisor_facts(_task_id)` and see what the supervisor saw
2. **Trace the decision**: The if/case logic is visible in the function body
3. **Verify without side effects**: Test the facts function without triggering retries or enqueues

For full details on facts functions, see [Facts, Logic, Effects](./facts-logic-effects.md).

### The no-SQL-in-body principle

For supervisors especially, avoid raw SQL in the function body:

```sql
-- BAD: inline SQL obscures the business logic
if (select count(*) from send_email_task_failed where task_id = _id) >= _max then
    ...
end if;
```

```sql
-- GOOD: named function makes intent clear
if _facts.num_failures >= _max_attempts then
    ...
end if;
```

The second version is readable as English: "if the number of failures is at least the max attempts, then..."

### Effect functions

Supervisors typically perform two kinds of effects:

1. **Schedule work**: Enqueue the actual task (email send, SMS send, etc.)
2. **Schedule self**: Re-enqueue the supervisor for the next check

Extract both into named functions:

```sql
-- Effect: schedule the actual email send
create or replace function comms.schedule_email_attempt(
    _send_email_task_id bigint
)
returns void
language plpgsql
as $$
begin
    insert into comms.send_email_task_scheduled (send_email_task_id)
    values (_send_email_task_id);

    perform queues.enqueue(
        'email',
        jsonb_build_object(
            'task_type', 'email',
            'send_email_task_id', _send_email_task_id,
            'before_handler', 'comms.get_email_payload',
            'success_handler', 'comms.record_email_success',
            'error_handler', 'comms.record_email_failure'
        ),
        now()
    );
end;
$$;

-- Effect: schedule supervisor recheck with exponential backoff
create or replace function comms.schedule_supervisor_recheck(
    _send_email_task_id bigint,
    _num_failures integer
)
returns void
language plpgsql
as $$
declare
    _base_delay_seconds integer := 5;
    _next_check_at timestamptz;
begin
    _next_check_at := now() + (
        _base_delay_seconds * power(2, _num_failures)
    ) * interval '1 second';

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'comms.send_email_supervisor',
            'send_email_task_id', _send_email_task_id
        ),
        _next_check_at
    );
end;
$$;
```

Now the supervisor body contains no INSERT statements and no `queues.enqueue` calls—just `perform` calls to named effect functions.

### Locking and concurrency

When multiple instances of a supervisor might run concurrently (e.g., two workers pick up the same task), you need to serialize access. Use `FOR UPDATE` to lock the root record before gathering facts.

```sql
-- Lock the root record before gathering facts
perform 1
from comms.send_email_task t
where t.send_email_task_id = _send_email_task_id
for update;

-- Now gather facts (within the same transaction, these are consistent)
_facts := comms.send_email_supervisor_facts(_send_email_task_id);
```

#### How FOR UPDATE blocking works

When supervisor A executes `SELECT ... FOR UPDATE`, it acquires a row-level lock. When supervisor B tries to execute the same `FOR UPDATE` on the same row, B **blocks** at that line and waits. B does not proceed to read facts while A holds the lock.

The sequence:

1. **A**: `FOR UPDATE` executes, lock acquired
2. **B**: `FOR UPDATE` executes, blocked waiting for A
3. **A**: reads facts, performs effects, commits transaction, lock released
4. **B**: lock acquired, now reads facts (fresh, including any changes A made)

Supervisor B sees the world *after* A is done, not during. This prevents double-scheduling and other race conditions.

#### Order matters

The lock must come before reading facts:

```sql
-- CORRECT: lock first, then read facts
perform 1 from task where id = _id for update;  -- blocks here if another holds it
_facts := get_facts(_id);  -- reads fresh data after lock acquired
```

```sql
-- WRONG: read facts first, then lock
_facts := get_facts(_id);  -- reads potentially stale data
perform 1 from task where id = _id for update;  -- too late, facts already gathered
```

In the wrong order, you might read facts, then block on the lock, then proceed with stale facts after the other transaction has changed the world.

### Payload design

Keep supervisor payloads minimal. A supervisor should receive just enough information to identify the work (typically a single task ID) and look up everything else inside the function.

**Why minimal payloads:**

1. **Prevents stale data**: If you pass file IDs in the payload, and a file is added or removed before the supervisor runs, the payload is wrong. Looking up file IDs inside means you always see the current state.

2. **Simplifies re-running**: When debugging, you can re-run a supervisor with just `{"task_id": 123}`. You don't need to reconstruct a complex payload.

3. **Reduces coupling**: The caller doesn't need to know what data the supervisor needs internally. It just provides the root identifier.

```sql
-- GOOD: minimal payload, look up details inside
create or replace function accounts.account_deletion_supervisor(
    payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
    _account_id bigint := (payload->>'account_id')::bigint;
    _file_ids bigint[];
begin
    -- Look up file IDs inside, not from payload
    select array_agg(f.file_id)
    into _file_ids
    from files.account_files(_account_id) f;
    
    -- ... rest of supervisor logic
end;
$$;
```

```sql
-- BAD: passing derived data in the payload
-- Caller must know about files, payload can become stale
perform queues.enqueue('db_function', jsonb_build_object(
    'db_function', 'accounts.account_deletion_supervisor',
    'account_id', _account_id,
    'file_ids', _file_ids,  -- stale if files change, look them up inside the supervisor
    'email_count', _email_count  -- unnecessary coupling
));
```

The exception is identifiers that the supervisor truly needs from the caller and cannot derive, like a parent task ID for tracing. But even then, prefer fewer fields over more.

For supervisors that orchestrate other supervisors (supervision trees), this principle is especially important. The parent supervisor should receive only its own task ID; child identifiers are discovered by querying current state. See [Supervision Trees](./supervision-trees.md) for more on hierarchical supervisor design.

### Debugging workflow

When a supervisor misbehaves:

1. **Get the task ID** from logs or the queue

2. **Check current facts**:
   ```sql
   select comms.send_email_supervisor_facts(12345);
   ```

3. **Trace the logic manually**: With facts in hand, read through the supervisor's if/case statements. You'll know exactly which branch it would take.

4. **Inspect fact tables directly** if needed:
   ```sql
   select * from comms.send_email_task_scheduled where send_email_task_id = 12345;
   select * from comms.send_email_task_failed where send_email_task_id = 12345;
   select * from comms.send_email_task_succeeded where send_email_task_id = 12345;
   ```

5. **Re-run the supervisor** if the issue was transient or you've fixed the data

### Common supervisor patterns

**Check terminal states first**:

```sql
if _facts.has_success then
    return 'succeeded';
end if;

if _facts.num_failures >= _max_attempts then
    return 'exhausted';
end if;
```

**Guard against double-scheduling**:

```sql
-- Only schedule if no outstanding attempt
if _facts.num_scheduled = _facts.num_failures then
    perform schedule_attempt(...);
end if;
```

**Always re-enqueue unless terminal**:

```sql
-- At the end of the function (before return)
perform schedule_supervisor_recheck(...);
```

### Expressions vs statements in logic

Keep logic as expressions when possible:

```sql
-- Expression-style (compact but can get complex)
return case
    when _facts.has_success then 'succeeded'
    when _facts.num_failures >= _max then 'exhausted'
    else 'in_progress'
end;
```

```sql
-- Statement-style (clearer for complex logic)
if _facts.has_success then
    return 'succeeded';
end if;

if _facts.num_failures >= _max then
    return 'exhausted';
end if;

return 'in_progress';
```

For supervisors with multiple effects (not just returns), statement-style is clearer. For pure decision functions with no effects, expression-style can be more concise.

### Run count protection

To prevent infinite supervisor loops (a bug that re-enqueues forever), add a run counter:

```sql
declare
    _run_count integer := coalesce((payload->>'run_count')::integer, 0);
    _max_runs integer := 20;
begin
    if _run_count >= _max_runs then
        raise exception 'supervisor exceeded max runs'
            using detail = 'Possible infinite loop detected';
    end if;

    -- ... normal logic ...

    -- When re-enqueuing, increment run_count
    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'db_function', 'comms.send_email_supervisor',
            'send_email_task_id', _task_id,
            'run_count', _run_count + 1
        ),
        _next_check_at
    );
end;
```

---

## Two stories

### Out-of-order events

Two webhooks arrive in any order; say, checkout completion and subscription creation. Each webhook handler writes its fact and then enqueues the supervisor. The supervisor checks what exists now: if both facts are present and one implies failure, it takes the failure path; if both are present and healthy, it records success; if one is still missing, it re-enqueues itself with a timeout (say, 30 minutes) and returns.

When the second webhook arrives, it enqueues the supervisor again. The supervisor now sees both facts and can proceed. If the second webhook never arrives, the timeout fires, the supervisor runs, sees only one fact, and can either extend the timeout or record a failure. No long-lived timers are held open in memory; the queue handles the waiting.

### Sending an email

We create a "send email" task and ask the supervisor to shepherd it. The first run sees no success, records one "scheduled" attempt, and enqueues the email. If the provider fails, the failure fact is written. The next run notices one failure and, if within limits, schedules exactly one more attempt. When success arrives, the supervisor sees the terminal fact and stops. The process is visible at every step and cannot double-schedule by accident because each decision is grounded in counts of facts.

---

## Summary checklist

- [ ] Facts gathered via a single `_facts := schema.supervisor_facts(_id)` call
- [ ] No raw SELECT/INSERT/UPDATE in the supervisor body
- [ ] Effects extracted to named functions
- [ ] Terminal states checked first (success, max attempts)
- [ ] Double-scheduling guarded with scheduled vs failed count
- [ ] Supervisor always re-enqueues itself unless terminal
- [ ] Run count protection to prevent infinite loops
- [ ] FOR UPDATE lock acquired before reading facts

### See also

- Hierarchical supervision: [`./supervision-trees.md`](./supervision-trees.md)
- Facts function pattern: [`./facts-logic-effects.md`](./facts-logic-effects.md)
- Queues and worker mechanics: [`../postgres/queues-and-worker.md`](../postgres/queues-and-worker.md)
