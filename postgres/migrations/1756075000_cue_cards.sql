-- auth helper: resolve account_id from JWT claim (PostgREST)
create or replace function auth.jwt_account_id()
returns bigint
stable
language sql
security definer
as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::bigint;
$$;

-- seed cue_cards config (idempotent)
insert into internal.config (
    key,
    value
)
values (
    'cue_cards',
    '{
        "recent_window_days": 2,
        "recency_reset_days": 2,
        "default_batch_size": 5,
        "default_language_code": "en"
    }'
)
on conflict (key) do nothing;

-- languages schema and domain
create schema if not exists languages;

create domain if not exists languages.language_code as text
    check (value in ('en','de','fr'));

-- cards schema: cue cards and translations
create schema if not exists cards;

create table if not exists cards.cue_card (
    cue_card_id bigserial primary key,
    created_at timestamp with time zone not null default now()
);

create table if not exists cards.cue_card_translation (
    cue_card_id bigint not null references cards.cue_card(cue_card_id) on delete cascade,
    language_code languages.language_code not null,
    title text not null,
    details text not null,
    created_at timestamp with time zone not null default now(),
    constraint cue_card_translation_pk primary key (cue_card_id, language_code)
);

-- learning schema: profiles, cycles, batches, facts
create schema if not exists learning;

create table if not exists learning.profile (
    profile_id bigserial primary key,
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    language_code languages.language_code not null,
    created_at timestamp with time zone not null default now(),
    constraint profile_unique_account_language unique (account_id, language_code)
);

create table if not exists learning.recency_cycle (
    recency_cycle_id bigserial primary key,
    profile_id bigint not null references learning.profile(profile_id) on delete cascade,
    started_at timestamp with time zone not null default now()
);

create table if not exists learning.recency_cycle_ended (
    recency_cycle_id bigint primary key references learning.recency_cycle(recency_cycle_id) on delete cascade,
    ended_at timestamp with time zone not null default now()
);

create table if not exists learning.selection_batch (
    selection_batch_id bigserial primary key,
    profile_id bigint not null references learning.profile(profile_id) on delete cascade,
    batch_size integer not null,
    created_at timestamp with time zone not null default now()
);

create table if not exists learning.selection_batch_item (
    selection_batch_id bigint not null references learning.selection_batch(selection_batch_id) on delete cascade,
    cue_card_id bigint not null references cards.cue_card(cue_card_id) on delete cascade,
    position_in_batch integer not null,
    created_at timestamp with time zone not null default now(),
    constraint selection_batch_item_pk primary key (selection_batch_id, cue_card_id),
    constraint selection_batch_item_position_unique unique (selection_batch_id, position_in_batch)
);

create table if not exists learning.selection_batch_dismissed (
    selection_batch_id bigint primary key references learning.selection_batch(selection_batch_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

create table if not exists learning.cue_card_seen (
    profile_id bigint not null references learning.profile(profile_id) on delete cascade,
    recency_cycle_id bigint not null references learning.recency_cycle(recency_cycle_id) on delete cascade,
    cue_card_id bigint not null references cards.cue_card(cue_card_id) on delete cascade,
    selection_batch_id bigint references learning.selection_batch(selection_batch_id) on delete set null,
    seen_at timestamp with time zone not null default now(),
    constraint cue_card_seen_pk primary key (profile_id, recency_cycle_id, cue_card_id, seen_at)
);

-- active profile history (append-only facts); most recent is authoritative
create table if not exists learning.active_profile_history (
    active_profile_history_id bigserial primary key,
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    profile_id bigint not null references learning.profile(profile_id) on delete cascade,
    recorded_at timestamp with time zone not null default now()
);

-- recency reset supervisor for worker (db_function task)
create or replace function learning.recency_reset_supervisor(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _recency_cycle_id bigint := (payload->>'recency_cycle_id')::bigint;
begin
    if _recency_cycle_id is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'missing_recency_cycle_id'
        );
    end if;

    perform 1
    from learning.recency_cycle rc
    where rc.recency_cycle_id = _recency_cycle_id
    for update;

    insert into learning.recency_cycle_ended (recency_cycle_id)
    values (_recency_cycle_id)
    on conflict (recency_cycle_id) do nothing;

    return jsonb_build_object('success', true);
end;
$$;

-- grant minimal rights for worker
grant usage on schema learning to worker_service_user;
grant execute on function learning.recency_reset_supervisor(jsonb) to worker_service_user;

-- fact helpers
create or replace function learning.get_default_language_code()
returns languages.language_code
stable
language sql
as $$
    select coalesce((internal.get_config('cue_cards')->>'default_language_code')::text, 'en')::languages.language_code;
$$;

create or replace function learning.get_default_batch_size()
returns integer
stable
language sql
as $$
    select coalesce((internal.get_config('cue_cards')->>'default_batch_size')::int, 5);
$$;

create or replace function learning.get_recent_window_days()
returns integer
stable
language sql
as $$
    select coalesce((internal.get_config('cue_cards')->>'recent_window_days')::int, 2);
$$;

create or replace function learning.get_recency_reset_days()
returns integer
stable
language sql
as $$
    select coalesce((internal.get_config('cue_cards')->>'recency_reset_days')::int, 2);
$$;

create or replace function learning.get_seen_cue_card_ids(
    _profile_id bigint,
    _recency_cycle_id bigint,
    _recent_window_days integer
)
returns bigint[]
stable
language sql
as $$
    select coalesce(
        array_agg(distinct s.cue_card_id),
        '{}'
    )
    from learning.cue_card_seen s
    where s.profile_id = _profile_id
      and (
          s.recency_cycle_id = _recency_cycle_id
          or (
              _recent_window_days > 0
              and s.seen_at >= now() - make_interval(days => _recent_window_days)
          )
      );
$$;

-- choose random cue card ids for a language, excluding provided ids
create or replace function learning.choose_random_cue_card_ids_for_language_excluding(
    _language_code languages.language_code,
    _exclude_ids bigint[],
    _limit integer
)
returns bigint[]
stable
language sql
as $$
    select coalesce(
        array_agg(x.cue_card_id),
        '{}'
    )
    from (
        select c.cue_card_id
        from cards.cue_card c
        join cards.cue_card_translation t
        using (cue_card_id)
        where t.language_code = _language_code
        and not (c.cue_card_id = any(coalesce(_exclude_ids, '{}')))
        order by random()
        limit _limit
    ) as x;
$$;

create or replace function learning.get_active_profile_for_account(
    _account_id bigint
)
returns learning.profile
stable
language sql
security definer
as $$
    select learning.profile.*
    from learning.profile
    join learning.active_profile_history
    using (profile_id)
    where active_profile_history.account_id = _account_id
    order by active_profile_history.recorded_at desc
    limit 1;
$$;

create or replace function learning.get_or_create_profile_for_account_language(
    _account_id bigint,
    _language_code languages.language_code
)
returns learning.profile
language plpgsql
security definer
as $$
declare
    _profile learning.profile;
begin
    select *
    into _profile
    from learning.profile
    where account_id = _account_id
    and language_code = _language_code;

    if _profile is null then
        insert into learning.profile (account_id, language_code)
        values (_account_id, _language_code)
        returning * into _profile;
    end if;

    return _profile;
end;
$$;

create or replace function learning.get_or_create_active_recency_cycle(
    _profile_id bigint
)
returns learning.recency_cycle
language plpgsql
security definer
as $$
declare
    _recency_cycle learning.recency_cycle;
begin
    select learning.recency_cycle.*
    into _recency_cycle
    from learning.recency_cycle
    left join learning.recency_cycle_ended using (recency_cycle_id)
    where learning.recency_cycle.profile_id = _profile_id
      and learning.recency_cycle_ended.recency_cycle_id is null
    order by learning.recency_cycle.started_at desc
    limit 1;

    if _recency_cycle.recency_cycle_id is null then
        insert into learning.recency_cycle (profile_id)
        values (_profile_id)
        returning * into _recency_cycle;
    end if;

    return _recency_cycle;
end;
$$;

-- helpers: selection batch
create or replace function learning.get_active_selection_batch(
    _profile_id bigint
)
returns learning.selection_batch
stable
language sql
security definer
as $$
    select learning.selection_batch.*
    from learning.selection_batch
    left join learning.selection_batch_dismissed using (selection_batch_id)
    where learning.selection_batch.profile_id = _profile_id
      and learning.selection_batch_dismissed.selection_batch_id is null
    order by learning.selection_batch.created_at desc
    limit 1;
$$;

create or replace function learning.dismiss_active_selection_batch(
    _selection_batch_id bigint
)
returns void
language plpgsql
security definer
as $$
    insert into learning.selection_batch_dismissed (selection_batch_id)
    values (_selection_batch_id)
    on conflict (selection_batch_id) do nothing;
$$;

create or replace function learning.get_selection_batch_cue_cards(
    _selection_batch_id bigint
)
returns jsonb[]
stable
language sql
as $$
    select array_agg(
        jsonb_build_object(
            'position', learning.selection_batch_item.position_in_batch,
            'cue_card_id', learning.selection_batch_item.cue_card_id,
            'title', cards.cue_card_translation.title,
            'details', cards.cue_card_translation.details
        )
    ) as items
    from learning.selection_batch_item
    join cards.cue_card_translation using (cue_card_id)
    where learning.selection_batch_item.selection_batch_id = _selection_batch_id
    order by learning.selection_batch_item.position_in_batch
$$;

-- helper: select cue card ids for a profile and batch size
create or replace function learning.select_cue_card_ids_for_profile(
    _profile learning.profile,
    _recency_cycle_id bigint,
    _batch_size integer
)
returns bigint[]
language plpgsql
stable
as $$
declare
    _recent_window_days integer := learning.get_recent_window_days();
    _seen_ids bigint[] := '{}';
    _chosen_ids bigint[] := '{}';
    _need integer := 0;
begin
    _seen_ids := learning.get_seen_cue_card_ids(
        _profile.profile_id,
        _recency_cycle_id,
        _recent_window_days
    );

    _chosen_ids := learning.choose_random_cue_card_ids_for_language_excluding(
        _profile.language_code,
        _seen_ids,
        _batch_size
    );

    _need := greatest(_batch_size - coalesce(array_length(_chosen_ids, 1), 0), 0);

    if _need > 0 then
        _chosen_ids := coalesce(
            array_cat(
                _chosen_ids,
                learning.choose_random_cue_card_ids_for_language_excluding(
                    _profile.language_code,
                    _chosen_ids,
                    _need
                )
            ),
            _chosen_ids
        );
    end if;

    return _chosen_ids;
end;
$$;

-- helper: create selection batch and items, returning selection_batch_id
create or replace function learning.create_selection_batch_with_items(
    _profile_id bigint,
    _cue_card_ids bigint[]
)
returns bigint
language plpgsql
security definer
as $$
declare
    _selection_batch_id bigint;
    _size integer := coalesce(array_length(_cue_card_ids, 1), 0);
begin
    insert into learning.selection_batch (profile_id, batch_size)
    values (_profile_id, _size)
    returning selection_batch_id into _selection_batch_id;

    insert into learning.selection_batch_item (selection_batch_id, cue_card_id, position_in_batch)
    select _selection_batch_id, x.cue_card_id, x.ordinal
    from unnest(coalesce(_cue_card_ids, '{}')) with ordinality as x(cue_card_id, ordinal);

    return _selection_batch_id;
end;
$$;

-- helper: record seen facts for all items in a selection batch
create or replace function learning.record_seen_for_selection_batch(
    _profile_id bigint,
    _recency_cycle_id bigint,
    _selection_batch_id bigint
)
returns void
language sql
security definer
as $$
    insert into learning.cue_card_seen (profile_id, recency_cycle_id, cue_card_id, selection_batch_id)
    select _profile_id, _recency_cycle_id, sbi.cue_card_id, _selection_batch_id
    from learning.selection_batch_item sbi
    where sbi.selection_batch_id = _selection_batch_id;
$$;

-- helper: enqueue recency reset for a cycle after configured delay
create or replace function learning.enqueue_recency_reset_for_cycle(
    _recency_cycle_id bigint
)
returns void
language plpgsql
security definer
as $$
declare
    _recency_reset_days integer := learning.get_recency_reset_days();
begin
    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'learning.recency_reset_supervisor',
            'recency_cycle_id', _recency_cycle_id
        ),
        now() + make_interval(days => _recency_reset_days)
    );
end;
$$;

-- RPC: set active profile by language (records a change)
create or replace function api.set_active_profile_by_language(
    language_code languages.language_code
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _account_id bigint := auth.jwt_account_id();
    _profile learning.profile;
begin
    if _account_id is null then
        raise exception 'Unauthorized'
            using detail = 'Missing Account',
                  hint = 'missing_account_id';
    end if;

    _profile := learning.get_or_create_profile_for_account_language(_account_id, language_code);

    insert into learning.active_profile_history (account_id, profile_id)
    values (_account_id, _profile.profile_id);

    return jsonb_build_object(
        'success', true,
        'profile', to_jsonb(_profile)
    );
end;
$$;

grant execute on function api.set_active_profile_by_language(languages.language_code) to authenticated;

-- RPC: get or create cue card batch
create or replace function api.get_or_create_cue_card_batch(
    limit integer default null,
    shuffle boolean default false
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _account_id bigint := auth.jwt_account_id();
    _profile learning.profile;
    _recency_cycle learning.recency_cycle;
    _active_batch learning.selection_batch;
    _batch_id bigint;
    _batch_size integer := coalesce(limit, learning.get_default_batch_size());
begin
    if _account_id is null then
        raise exception 'Unauthorized'
            using detail = 'Missing Account',
                  hint = 'missing_account_id';
    end if;

    _profile := learning.get_active_profile_for_account(_account_id);

    if _profile is null then
        raise exception 'No active profile found'
            using detail = 'No Active Profile',
                  hint = 'no_active_profile';
    end if;

    _recency_cycle := learning.get_or_create_active_recency_cycle(_profile.profile_id);
    
    _active_batch := learning.get_active_selection_batch(_profile.profile_id);

    -- return active batch if shuffle is false and active batch exists
    if coalesce(shuffle, false) = false and _active_batch is not null then
       return jsonb_build_object(
            'selection_batch_id', _active_batch.selection_batch_id,
            'items', learning.get_selection_batch_cue_cards(_active_batch.selection_batch_id)
        );
    end if;

    if coalesce(shuffle, false) = true and _active_batch is not null then
        learning.dismiss_active_selection_batch(_active_batch.selection_batch_id);
    end if;

    -- select candidate cue card ids and create batch with items
    _batch_id := learning.create_selection_batch_with_items(
        _profile.profile_id,
        learning.select_cue_card_ids_for_profile(
            _profile,
            _recency_cycle.recency_cycle_id,
            _batch_size
        )
    );

    -- record seen facts for the batch
    perform learning.record_seen_for_selection_batch(
        _profile.profile_id,
        _recency_cycle.recency_cycle_id,
        _batch_id
    );

    -- schedule recency reset
    perform learning.enqueue_recency_reset_for_cycle(_recency_cycle.recency_cycle_id);

    return jsonb_build_object(
        'selection_batch_id', _batch_id,
        'items', learning.get_selection_batch_cue_cards(_batch_id)
    );
end;
$$;

grant execute on function api.get_or_create_cue_card_batch(integer, boolean) to authenticated;
