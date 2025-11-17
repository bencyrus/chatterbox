<!-- f5c8cebf-c2df-4f6b-89bc-e19646141a5a 02a492e8-79f3-435d-b4f8-ecc62629b014 -->
# Cue Cards Implementation Proposal

Status: future

Last verified: 2025-10-22

← Back to [`docs/postgres/README.md`](README.md)

### Why this exists

- Serve short, multilingual cue cards for speaking practice with predictable, idempotent behavior.
- Keep state append-only and derive selection from facts, following our supervisor/worker model.

### Role in the system

- **Schemas**: `languages` (domain), `cards` (card identities + translations), `learning` (profiles, cycles, batches, seen facts).
- **Config**: `internal.config('cue_cards')` → `{ "recent_window_days": 2, "recency_reset_days": 2, "default_batch_size": 5 }`.
- **API**: PostgREST RPC `api.get_or_create_cue_card_batch` returns a stable batch until shuffled.
- **Auth**: `account_id` comes from JWT (`sub`); helper `auth.jwt_account_id()` resolves it inside SQL.

### Data model (append-only where applicable)

- `languages` schema
```sql
create schema if not exists languages;
-- For now, a simple domain with a fixed set; can evolve to a table later
create domain languages.language_code as text check (value in ('en','de','fr'));
```

- `cards` schema
```sql
create schema if not exists cards;

-- Root identity (language-agnostic)
create table cards.cue_card (
  cue_card_id bigserial primary key,
  created_at timestamptz not null default now()
);

-- Localized content
create table cards.cue_card_translation (
  cue_card_id bigint not null references cards.cue_card(cue_card_id) on delete cascade,
  language_code languages.language_code not null,
  title text not null,
  details text not null,
  created_at timestamptz not null default now(),
  constraint cue_card_translation_pk primary key (cue_card_id, language_code)
);

-- Convenience view for API/admin browsing
create or replace view cards.localized_cue_cards as
select c.cue_card_id, t.language_code, t.title, t.details
from cards.cue_card c
join cards.cue_card_translation t using (cue_card_id);
```

- `learning` schema
```sql
create schema if not exists learning;

-- Per-account, per-language profile
create table learning.profile (
  profile_id bigserial primary key,
  account_id bigint not null references accounts.account(account_id) on delete cascade,
  language_code languages.language_code not null,
  created_at timestamptz not null default now(),
  constraint profile_unique_account_language unique (account_id, language_code)
);

-- Active recency window (append-only facts for start/end)
create table learning.recency_cycle (
  recency_cycle_id bigserial primary key,
  profile_id bigint not null references learning.profile(profile_id) on delete cascade,
  started_at timestamptz not null default now()
);

create table learning.recency_cycle_ended (
  recency_cycle_id bigint primary key references learning.recency_cycle(recency_cycle_id) on delete cascade,
  ended_at timestamptz not null default now()
);

-- Selection batches and items (append-only)
create table learning.selection_batch (
  selection_batch_id bigserial primary key,
  profile_id bigint not null references learning.profile(profile_id) on delete cascade,
  batch_size integer not null,
  created_at timestamptz not null default now()
);

create table learning.selection_batch_item (
  selection_batch_id bigint not null references learning.selection_batch(selection_batch_id) on delete cascade,
  cue_card_id bigint not null references cards.cue_card(cue_card_id) on delete cascade,
  position_in_batch integer not null,
  created_at timestamptz not null default now(),
  constraint selection_batch_item_pk primary key (selection_batch_id, cue_card_id),
  constraint selection_batch_item_position_unique unique (selection_batch_id, position_in_batch)
);

-- Dismissal fact when user shuffles (append-only)
create table learning.selection_batch_dismissed (
  selection_batch_id bigint primary key references learning.selection_batch(selection_batch_id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Seen fact recorded when batch is created (append-only)
create table learning.cue_card_seen (
  profile_id bigint not null references learning.profile(profile_id) on delete cascade,
  recency_cycle_id bigint not null references learning.recency_cycle(recency_cycle_id) on delete cascade,
  cue_card_id bigint not null references cards.cue_card(cue_card_id) on delete cascade,
  selection_batch_id bigint references learning.selection_batch(selection_batch_id) on delete set null,
  seen_at timestamptz not null default now(),
  constraint cue_card_seen_pk primary key (profile_id, recency_cycle_id, cue_card_id, seen_at)
);
```

- Indices (minimal, for responsiveness)
```sql
create index if not exists cue_card_translation_lang on cards.cue_card_translation(language_code);
create index if not exists seen_profile_cycle on learning.cue_card_seen(profile_id, recency_cycle_id);
create index if not exists selection_items_selection on learning.selection_batch_item(selection_batch_id);
```


### Configuration

- Source: `internal.config('cue_cards')` with keys:
  - `recent_window_days` (short-term avoidance window),
  - `recency_reset_days` (when to end current cycle),
  - `default_batch_size` (fallback for `limit`).

### Selection behavior

- First use per account+language creates a `learning.profile` and an active `learning.recency_cycle` if missing.
- Active batch: latest `learning.selection_batch` for a profile without a corresponding `selection_batch_dismissed`.
- If `shuffle=false`, return the active batch as-is.
- If `shuffle=true`, mark active batch dismissed and create a new batch.
- Avoid cards seen in the active recency cycle (and optionally within `recent_window_days`). If fewer than `limit`, fill from the remaining catalog. If everything has been seen, fall back to fresh random from full catalog.
- Each new batch writes: one `selection_batch` row; N `selection_batch_item` rows with deterministic positions; N `cue_card_seen` facts tied to the active `recency_cycle_id`.
- Schedule a recency reset supervisor at `now() + recency_reset_days` to end the cycle.

Randomness:

- Initial implementation may use `order by random()`; for large catalogs consider salted hash ordering later.

### Auth helper

- Extract caller `account_id` from JWT claim via PostgREST.
```sql
create or replace function auth.jwt_account_id()
returns bigint
stable
language sql
security definer
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::bigint;
$$;
```


### RPC (PostgREST)

- Signature: `api.get_or_create_cue_card_batch(language_code languages.language_code, limit int default null, shuffle boolean default false) → jsonb`.
- Behavior:
  - Resolve `account_id` via `auth.jwt_account_id()`.
  - Ensure `learning.profile` and active `learning.recency_cycle` exist.
  - If `shuffle=false` and an active batch exists → return it.
  - Else select new items obeying avoidance rules, create batch, items, seen facts, and schedule recency reset.
  - Return shape:
```json
{
  "selection_batch_id": 123,
  "language_code": "en",
  "items": [
    { "cue_card_id": 10, "title": "Talk about your day", "details": "1) ..." }
  ]
}
```

- Security:
  - Function is `security definer`.
  - `grant execute on function api.get_or_create_cue_card_batch(...) to authenticated;`
  - View `cards.localized_cue_cards` may be readable by `anon, authenticated` for admin/browse UIs.

### Recency reset supervisor (worker integration)

- Purpose: end the active recency cycle at scheduled time to “start fresh” next time.
- Task type: `db_function` (aligns with existing worker contract).
- Location: `learning.recency_reset_supervisor(payload jsonb)` returning a JSON envelope.
```sql
create or replace function learning.recency_reset_supervisor(payload jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  _recency_cycle_id bigint := (payload->>'recency_cycle_id')::bigint;
begin
  if _recency_cycle_id is null then
    return jsonb_build_object('success', false, 'validation_failure_message', 'missing_recency_cycle_id');
  end if;

  perform 1 from learning.recency_cycle where recency_cycle_id = _recency_cycle_id for update;

  insert into learning.recency_cycle_ended(recency_cycle_id)
  values (_recency_cycle_id)
  on conflict (recency_cycle_id) do nothing;

  return jsonb_build_object('success', true);
end;
$$;
```

- Enqueue when creating a new batch:
```sql
perform queues.enqueue(
  'db_function',
  jsonb_build_object(
    'task_type','db_function',
    'db_function','learning.recency_reset_supervisor',
    'recency_cycle_id', /* active cycle id */
    'scheduled_by', 'cue_cards'
  ),
  now() + make_interval(days => _recency_reset_days)
);
```

- Grants to worker:
```sql
grant usage on schema learning to worker_service_user;
grant execute on function learning.recency_reset_supervisor(jsonb) to worker_service_user;
```


### Grants (minimum)

```sql
grant select on cards.localized_cue_cards to anon, authenticated;
-- API RPC
grant usage on schema api to authenticated;
-- The RPC itself will be granted after creation
```

### Safety and standards

- Append-only facts; no deletes/updates in normal flows.
- No PII in logs; selection RPC reads JWT claim via PostgREST and never logs tokens.
- Follow the SQL style guide conventions (multi-line, clear clauses, avoid unnecessary aliases).

### Future (not implemented)

- Salted, hash-based sampling for large catalogs.
- Tags/taxonomy and filtered selection.
- Per-language overrides in `internal.config('cue_cards')`.
- Admin RPCs to create cards with initial translations.

### See also

- `docs/postgres/sql-style-guide.md`
- `docs/postgres/queues-and-worker.md`
- `docs/postgres/security.md`
- `docs/worker/payloads.md`

### To-dos

- [ ] Add schemas/tables/views for languages, cards, learning (append-only facts)
- [ ] Implement API RPC get_or_create_cue_card_batch with avoidance rules
- [ ] Add learning.recency_reset_supervisor and enqueue from RPC
- [ ] Grant minimal execute/select to roles and worker