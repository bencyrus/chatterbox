-- schema: cue cards and their localized content
create schema if not exists cues;
grant usage on schema cues to authenticated;

create domain cues.stage as text
    check (value in ('draft', 'published', 'archived'));

-- table: root cue card (language-independent metadata)
create table if not exists cues.cue (
    cue_id bigserial primary key,
    created_at timestamp with time zone not null default now(),
    created_by bigint not null references accounts.account(account_id) on delete cascade
);

-- table: cue stage transitions (tracks all stage changes)
create table if not exists cues.cue_stage (
    cue_stage_id bigserial primary key,
    cue_id bigint not null references cues.cue(cue_id) on delete cascade,
    stage cues.stage not null,
    created_at timestamp with time zone not null default now(),
    created_by bigint not null references accounts.account(account_id) on delete cascade
);


-- function: get current stage for a cue
create or replace function cues.current_stage(_cue_id bigint)
returns cues.stage
language sql
stable
as $$
    select stage
    from cues.cue_stage
    where cue_id = _cue_id
    order by created_at desc, cue_stage_id desc
    limit 1;
$$;

-- function: get full stage history for a cue
create or replace function cues.stage_history(_cue_id bigint)
returns jsonb
language sql
stable
as $$
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'stage', cs.stage,
                'created_at', cs.created_at,
                'created_by', cs.created_by
            )
            order by cs.created_at desc, cs.cue_stage_id desc
        ),
        '[]'::jsonb
    )
    from cues.cue_stage cs
    where cs.cue_id = _cue_id;
$$;

-- table: localized cue content for a cue (one row per language)
create table if not exists cues.cue_content (
    cue_content_id bigserial primary key,
    cue_id bigint not null references cues.cue(cue_id) on delete cascade,
    title text not null,
    details text not null,
    language_code languages.language_code not null,
    created_at timestamp with time zone not null default now(),
    constraint cue_content_unique unique (cue_id, language_code)
);

-- function: normalize cue + content into a consistent jsonb representation
create or replace function cues.build_cue_with_content(
    _cue cues.cue,
    _content cues.cue_content
)
returns jsonb
language sql
stable
as $$
    select to_jsonb(_cue)
           || jsonb_build_object('stage', cues.current_stage(_cue.cue_id))
           || jsonb_build_object('content', to_jsonb(_content));
$$;
