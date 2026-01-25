## Facts, Logic, Effects

Status: current
Last verified: 2025-01-25

← Back to [`docs/patterns/README.md`](./README.md)

### Why this pattern

Business functions often become tangled: database lookups mixed with conditionals mixed with writes. When something goes wrong, it's hard to know what the function saw, what it decided, and what it did. This pattern separates those concerns into three distinct phases.

### The three phases

1. **Facts** – Gather all the information needed to make a decision. This is read-only.
2. **Logic** – Make the decision based purely on the facts. Don't read from/write into the database.
3. **Effects** – Perform the writes and side effects based on the decision.

```
┌─────────────────────────────────────────────────────────────────┐
│                      Business Function                          │
├─────────────────────────────────────────────────────────────────┤
│  FACTS     │  Gather all data needed (stable, read-only)        │
├─────────────────────────────────────────────────────────────────┤
│  LOGIC     │  if/case statements, pure decision making          │
├─────────────────────────────────────────────────────────────────┤
│  EFFECTS   │  Writes, inserts, enqueues (each a named function) │
└─────────────────────────────────────────────────────────────────┘
```

### Why this separation matters

**Debugging**: When something fails, you can re-run just the facts phase on the same input. You see exactly what the function would have seen. No guessing.

**Testing**: You can call the facts function independently, inspect the result, and verify your logic would branch correctly—without triggering any side effects.

**Development**: When fixing a bug, you want to know what control flow the function will follow. Call the facts function, inspect the result, predict the behavior. The function becomes observable.

**Readability**: The main function becomes a simple sequence: get facts, check conditions, call effects. The business logic is visible at a glance.

### What "no SQL in the body" means

In an ideal implementation, the main function body has no raw SELECT, INSERT, or UPDATE statements. Instead:

- All reads go through a **facts function** (which can be a single aggregated call or multiple small stable functions)
- All logic uses **procedural control flow** (`if/elsif/else`, `case/when`, `for/while` loops), which are plpgsql constructs rather than SQL queries
- All writes go through **effect functions** (named, single-purpose functions that perform the writes)

The main function becomes pure orchestration:

```
facts := get_facts(input);
if facts.some_condition then
    perform do_effect_a(input);
else
    perform do_effect_b(input);
end if;
```

### When to apply this pattern

This pattern is most valuable for:

- **Workflow orchestration** (supervisors, state machines)
- **Business processes** with multiple possible outcomes
- **Any function you might need to debug in production**

For simple CRUD operations or trivial getters, the overhead isn't worth it.

### Trade-offs

**More functions**: You'll write more small functions instead of fewer large ones. This is a feature because each function is testable and observable.

**Potential for stale reads**: If facts are gathered early and effects happen later, the world might change in between. In PostgreSQL, this is mitigated by transaction isolation, but be aware of it in eventual-consistency systems.

**Gathering facts you might not use**: By collecting all facts upfront, you may query data that an early return makes irrelevant. For example, if `has_success` is true, you never needed `num_failures`. This is intentional and the performance cost is negligible: primary key and foreign key lookups are sub-millisecond operations. The alternative, conditional lookups, or multiple facts functions for different code paths, adds complexity that far outweighs the cost of a few extra index hits. If a facts function ever does something expensive (full table scan, complex join), reconsider its design, but simple counts and exists checks on indexed columns are not worth optimizing.

---

## Implementing facts functions in PostgreSQL

This section documents how to implement the facts-logic-effects pattern in PostgreSQL/plpgsql.

### The structure of a facts function

A facts function:

- Takes an identifier (e.g., `_task_id`)
- Returns a record with all the data needed for decisions
- Is marked `stable` (read-only, same inputs = same outputs within a transaction)
- Uses `language sql` when possible for simplicity

#### Basic example

```sql
create or replace function comms.send_email_supervisor_facts(
    _send_email_task_id bigint
)
returns record
language sql
stable
as $$
    select
        comms.has_send_email_task_succeeded(_send_email_task_id) as has_success,
        comms.count_send_email_task_failures(_send_email_task_id) as num_failures,
        comms.count_send_email_task_scheduled(_send_email_task_id) as num_scheduled;
$$;
```

#### Alternative: inline queries instead of helper functions

If you don't need the individual helpers elsewhere, you can write the queries directly in the facts function:

```sql
create or replace function comms.send_email_supervisor_facts(
    _send_email_task_id bigint
)
returns record
language sql
stable
as $$
    select
        exists (
            select 1
            from comms.send_email_task_succeeded s
            where s.send_email_task_id = _send_email_task_id
        ) as has_success,
        (
            select count(*)::integer
            from comms.send_email_task_failed f
            where f.send_email_task_id = _send_email_task_id
        ) as num_failures,
        (
            select count(*)::integer
            from comms.send_email_task_scheduled s
            where s.send_email_task_id = _send_email_task_id
        ) as num_scheduled;
$$;
```

Both approaches work:

- **Inline queries**: Use when the facts are specific to one function. Simpler, fewer steps to understand the query.
- **Helper functions**: Use when individual facts are reused elsewhere, or when you want each fact callable independently for debugging.

### Usage in the calling function

```sql
declare
    _facts record;
begin
    _facts := comms.send_email_supervisor_facts(_send_email_task_id);

    if _facts.has_success then
        return jsonb_build_object('status', 'already_succeeded');
    end if;

    if _facts.num_failures >= _max_attempts then
        return jsonb_build_object('status', 'max_attempts_reached');
    end if;

    -- ... logic continues
end;
```

### Full calling function example

With facts extracted, the main function becomes pure orchestration:

```sql
create or replace function comms.send_email_supervisor(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_email_task_id bigint := (payload->>'send_email_task_id')::bigint;
    _facts record;
    _max_attempts integer := 2;
begin
    -- VALIDATION
    if _send_email_task_id is null then
        return jsonb_build_object('error', 'missing_send_email_task_id');
    end if;

    -- FACTS
    _facts := comms.send_email_supervisor_facts(_send_email_task_id);

    -- LOGIC + EFFECTS
    if _facts.has_success then
        return jsonb_build_object('status', 'succeeded');
    end if;

    if _facts.num_failures >= _max_attempts then
        return jsonb_build_object('status', 'max_attempts_reached');
    end if;

    if _facts.num_scheduled = _facts.num_failures then
        perform comms.schedule_email_attempt(_send_email_task_id);
    end if;

    perform comms.schedule_supervisor_recheck(_send_email_task_id, _facts.num_failures);

    return jsonb_build_object('status', 'scheduled');
end;
$$;
```

Notice:

- No raw `select ... from` in the body
- No inline `insert` statements (these become named effect functions)
- The logic is visible: check success, check max attempts, schedule if needed

### Benefits of the facts function

**Debugging in production**: When a supervisor misbehaves, run:

```sql
select comms.send_email_supervisor_facts(12345);
```

You see exactly what the function would see. No side effects. Compare against expected values.

**Testing without side effects**: In development, call the facts function to verify your test setup is correct before running the full function:

```sql
-- Set up test data
insert into comms.send_email_task_failed (...);

-- Verify facts before running supervisor
select comms.send_email_supervisor_facts(_task_id);
-- Check: does num_failures match what you expect?
```

**Predictable control flow**: If you're unsure which branch a function will take, call the facts function first. The main function's logic should be so simple that, given the facts, you can trace the path by hand.

### Effect functions

Just as facts are extracted, effects should be too:

```sql
-- Effect: record a scheduled attempt
create or replace function comms.schedule_email_attempt(
    _send_email_task_id bigint
)
returns void
language plpgsql
security definer
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
```

### Avoiding stale facts

When multiple instances of a function might run concurrently (e.g., two workers pick up the same supervisor), you need to serialize access. Use `FOR UPDATE` to lock the root record before gathering facts.

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

### Common mistakes

**Mixing facts and effects**: Don't do this:

```sql
-- BAD: facts and effects interleaved
select count(*) into _failures from task_failed where ...;
insert into task_scheduled ...;  -- effect before all facts gathered
select has_success into _done from ...;  -- more facts after an effect
```

**Inline SQL in the main body**: Don't do this:

```sql
-- BAD: raw SQL scattered through the function
if (select count(*) from task_failed where task_id = _id) >= 3 then
    ...
end if;
```

Instead, call a named facts function.

**Side effects in facts functions**: A facts function must be stable (no writes). If you find yourself wanting to insert or update inside a facts function, you've misunderstood the pattern.

### See also

- Supervisor-specific patterns: [`./supervisors.md`](./supervisors.md)
- SQL formatting conventions: [`../postgres/sql-style-guide.md`](../postgres/sql-style-guide.md)
- Queues and worker mechanics: [`../postgres/queues-and-worker.md`](../postgres/queues-and-worker.md)
