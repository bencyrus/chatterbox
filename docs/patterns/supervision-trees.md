## Supervision Trees

Status: current
Last verified: 2025-01-25

← Back to [`docs/patterns/README.md`](./README.md)

### Why supervision trees

A single supervisor handles one workflow: check state, decide, act, repeat. But real systems often have workflows that spawn sub-workflows. Account deletion doesn't just "delete the account"; it deletes files, anonymizes data, and cleans up related records. Each of those sub-steps might fail independently, retry on their own schedules, and need their own supervision.

A supervision tree is a hierarchy of supervisors where a parent supervisor orchestrates child supervisors (or child tasks). The parent doesn't micromanage every step of the children; it kicks them off, then waits until it's time to check again. The children handle their own retries and failure logic, and can optionally trigger the parent to run immediately when they complete.

### Erlang/OTP origins

The supervision tree pattern comes from Erlang/OTP, where it forms the backbone of fault-tolerant systems. In Erlang:

- **Workers** are processes that do actual work
- **Supervisors** are processes that monitor workers and restart them on failure
- Supervisors can supervise other supervisors, forming a tree

The key insight is that failure handling is separated from business logic. A worker does its job and crashes if something unexpected happens. The supervisor decides what to do about that crash: restart, retry with backoff, or give up. This separation keeps business logic simple and makes failure recovery explicit.

In traditional Erlang, supervisors receive crash signals from their children and respond immediately. Our PostgreSQL adaptation works differently. Supervisors don't receive signals; instead, they either poll the state on a schedule or the child supervisor enqueues the parent to run immediately upon completion. But the core principle remains: hierarchical responsibility, where each level handles its own concerns.

### How it applies to PostgreSQL supervisors

In our system, a supervision tree looks like this:

```
Root supervisor (e.g., account_deletion_supervisor)
├── Kicks off child tasks/supervisors
├── Schedules itself to re-check later
└── On each run: queries state to see if children are done

Child supervisor (e.g., file_deletion_supervisor)
├── Handles its own retries and backoff
├── Records success/failure facts
├── Can enqueue parent supervisor on completion
└── Terminates when done or stuck
```

The root supervisor doesn't block waiting for children to signal completion. Instead, it runs periodically—either on a schedule (say, every 30 seconds) or when a child enqueues it upon completion. Each time it runs, it checks the current state: "Are all files deleted? Is anonymization complete?" If yes, proceed. If no, schedule another check.

This state-checking approach has a crucial property: **the parent can run at any time without causing incorrect behavior**. Even if the parent runs "early" (before children finish), it simply observes incomplete state and waits. Even if it runs "late" (long after children finish), it observes complete state and proceeds. The system is correct regardless of timing.

### The key principle: never assume ordering

In a supervision tree, the parent supervisor might run before, during, or after its children complete. You cannot assume any particular ordering. This leads to a fundamental rule:

**Always check state before proceeding. Never assume a child is done just because you kicked it off.**

```sql
-- WRONG: assuming file deletion is done because we started it
perform kick_off_file_deletion(_file_id);
-- immediately proceed to anonymization...

-- RIGHT: check whether file deletion is actually complete
if not files.all_account_files_deleted(_account_id) then
    -- schedule self to check again later
    perform schedule_recheck(...);
    return;
end if;
-- now safe to proceed to anonymization
```

This might feel repetitive—you're constantly re-checking things that "should" be done. But this repetition is what makes the system reliable. If a child supervisor fails, retries, and eventually succeeds, the parent will eventually see that success. If a child gets stuck, the parent will notice (via stuck detection) and can record its own failure.

### Designing a supervision tree

When designing a supervision tree, think about:

**1. What are the phases?**

Break the workflow into sequential phases where each phase must complete before the next begins. For account deletion:
- Phase 1: Delete all user files
- Phase 2: Anonymize account data
- Phase 3: Mark deletion complete

**2. Which phases need their own supervisors?**

A phase needs its own supervisor when:
- It involves external systems that might fail (storage, APIs)
- It has multiple items to process (many files, many records)
- It needs independent retry logic

File deletion needs its own supervisor because each file deletion involves external storage and might fail independently. Anonymization might be simple enough to inline, or complex enough to warrant its own supervisor—depends on the data volume.

**3. How does the parent track child completion?**

The parent needs to query whether each phase is complete. This typically means:
- A facts function that checks child state: `all_files_deleted(_account_id)`
- Or checking for a terminal fact: `has_anonymization_succeeded(_account_id)`

**4. What happens when children fail permanently?**

Define stuck detection at each level. If file deletion fails 3 times for a particular file, `is_file_deletion_stuck(_file_id)` returns true. The parent checks for stuck children and records its own failure when it can't proceed.

### Account deletion example

Here's how account deletion implements a supervision tree:

```
account_deletion_supervisor (root)
│
├─► Phase 1: File deletion
│   ├── For each file: kick off file_deletion_supervisor
│   ├── Check: files.all_account_files_deleted(_account_id)?
│   └── If any file stuck: record failure, stop
│
├─► Phase 2: Anonymization
│   ├── Kick off account_anonymization_supervisor
│   ├── Check: accounts.has_anonymization_succeeded(_account_id)?
│   └── If stuck: record failure, stop
│
└─► Phase 3: Complete
    └── Record account_deletion_task_succeeded
```

The root supervisor's logic looks like:

```sql
-- Simplified account_deletion_supervisor logic

-- Check terminal states
if _facts.has_success then
    return 'already_succeeded';
end if;

if _facts.has_failure then
    return 'already_failed';
end if;

-- Phase 1: File deletion
if not _facts.all_files_deleted then
    -- Are any files stuck?
    if _facts.any_file_stuck then
        perform record_deletion_failure(_task_id, 'file_deletion_stuck');
        return 'failed';
    end if;
    
    -- Kick off file deletion for files that don't have tasks yet
    perform kick_off_pending_file_deletions(_account_id);
    
    -- Schedule recheck and exit
    perform schedule_recheck(_task_id);
    return 'waiting_for_files';
end if;

-- Phase 2: Anonymization
if not _facts.is_anonymized then
    if _facts.anonymization_stuck then
        perform record_deletion_failure(_task_id, 'anonymization_stuck');
        return 'failed';
    end if;
    
    perform kick_off_anonymization(_account_id);
    perform schedule_recheck(_task_id);
    return 'waiting_for_anonymization';
end if;

-- Phase 3: All done
perform record_deletion_success(_task_id);
return 'succeeded';
```

Each phase checks its precondition before proceeding. The supervisor doesn't know or care how long file deletion takes—it just checks whether files are deleted. If they're not, it schedules another check and exits.

### Child supervisor independence

Each child supervisor (like `file_deletion_supervisor`) is fully independent:

- It has its own task tables: `file_deletion_task`, `file_deletion_task_failed`, etc.
- It handles its own retry logic and backoff
- It records its own success/failure facts
- It doesn't know it's part of a larger tree

This independence is important. The file deletion supervisor can be used by account deletion today and by some other workflow tomorrow. It doesn't need to know its caller.

The parent-child relationship exists only in:
1. The parent's logic (checking child state)
2. The payload (parent might pass its task ID for tracing)

### When to use a supervision tree vs a flat supervisor

**Use a flat supervisor when:**
- The workflow has a single unit of work (send one email)
- Retries apply to the whole operation
- There are no independent sub-processes

**Use a supervision tree when:**
- The workflow has multiple independent sub-processes
- Sub-processes might fail and retry independently
- You need to track progress through phases
- The workflow involves cleanup of multiple resources

The sending email supervisor is flat: one task, one outcome. The account deletion supervisor is a tree: multiple files, each with its own deletion lifecycle, followed by anonymization with its own lifecycle.

### Timing and scheduling

There are two ways to trigger the parent supervisor:

**1. Scheduled polling**: The parent schedules itself to run again after a delay. How long should it wait? Consider:
- **Long enough** for children to make progress (no point checking every 100ms if file deletion takes seconds)
- **Short enough** that the workflow doesn't stall unnecessarily
- **Proportional** to the expected work: more files might mean longer intervals

A common pattern is exponential backoff based on how many times you've checked without progress. First check after 5 seconds, then 10, then 20, up to some maximum.

**2. Child-triggered**: The child supervisor enqueues the parent to run immediately when it completes (success or permanent failure). This reduces latency—the parent proceeds as soon as possible rather than waiting for its next scheduled run.

You can combine both approaches: children trigger the parent on completion, and the parent also schedules periodic rechecks as a safety net. Even with child triggers, the parent should verify state rather than trusting the trigger—triggers can arrive out of order or be duplicated.

### Failure propagation

When a child fails permanently, the parent needs to know. This happens through state:

1. Child records failure facts until stuck detection triggers
2. Parent queries `is_child_stuck(_id)` as part of its facts
3. Parent sees stuck state and records its own failure

The parent doesn't receive a crash signal; it discovers the stuck state on its next run. The child can enqueue the parent immediately when it becomes stuck, or the parent discovers it during a scheduled recheck—either way, the parent needs to run to notice child failures.

### Summary

| Concept | Implementation |
|---------|----------------|
| Parent supervisor | Orchestrates phases, checks child state, schedules itself |
| Child supervisor | Independent, handles own retries, records own facts, can trigger parent |
| State checking | Parent queries facts, never assumes completion |
| Stuck detection | Each level defines when to give up |
| Timing | Scheduled rechecks, child-triggered runs, or both |

The supervision tree pattern gives you:
- **Isolation**: Child failures don't corrupt parent state
- **Visibility**: Each level has its own facts to inspect
- **Resilience**: The system makes progress regardless of timing
- **Composability**: Child supervisors can be reused in different trees

### See also

- Single supervisor patterns: [`./supervisors.md`](./supervisors.md)
- Facts function pattern: [`./facts-logic-effects.md`](./facts-logic-effects.md)
- Account deletion implementation: [`../postgres/account-deletion.md`](../postgres/account-deletion.md)
- Exception handling: [`./exception-handling.md`](./exception-handling.md)
