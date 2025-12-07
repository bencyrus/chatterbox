-- schema: files metadata and lookup for file service
create schema if not exists files;

-- files service user with minimal grants
create user file_service_user with login password '{secrets.file_service_user_password}';
grant usage on schema files to file_service_user;

-- domain: mime type for shared files
create domain files.mime_type as text
    check (value in ('image/jpeg', 'image/png', 'audio/mp4'));

-- domain: metadata key for file_metadata.key
create domain files.metadata_key as text
    check (value in ('name'));

-- table: generic file record for any shared file asset
create table if not exists files.file (
    file_id bigserial primary key,
    bucket text not null,
    object_key text not null unique,
    mime_type files.mime_type not null,
    created_at timestamp with time zone not null default now()
);

-- table: arbitrary key/value metadata attached to a file
create table if not exists files.file_metadata (
    file_metadata_id bigserial primary key,
    file_id bigint not null references files.file(file_id) on delete cascade,
    key files.metadata_key not null,
    value jsonb not null,
    created_at timestamp with time zone not null default now(),
    constraint file_metadata_unique_file_key unique (file_id, key)
);

-- function: lookup file metadata for an array of file ids
create or replace function files.lookup_files(
    _file_ids bigint[]
)
returns jsonb
language sql
stable
security definer
as $$
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'file_id', f.file_id,
                'bucket', f.bucket,
                'object_key', f.object_key,
                'mime_type', f.mime_type
            )
            order by f.file_id
        ),
        '[]'::jsonb
    )
    from files.file f
    where _file_ids is not null
      and f.file_id = any(_file_ids);
$$;

grant execute on function files.lookup_files(bigint[]) to file_service_user;

-- config: GCS bucket name
insert into internal.config (
    key,
    value
)
values (
    'gcs_bucket',
    to_jsonb('{secrets.gcs_chatterbox_bucket}'::text)
)
on conflict (key) do nothing;

-- function: get GCS bucket name from config
create or replace function files.gcs_bucket()
returns text
stable
language sql
as $$
    select (internal.get_config('gcs_bucket') #>> '{}')::text;
$$;

-- seed: app icon file stored in GCS
insert into files.file (
    bucket,
    object_key,
    mime_type
)
values (
    files.gcs_bucket(),
    'internal-assets/chatterbox-logo-color-bg.png',
    'image/png'
)
on conflict (object_key) do nothing;

insert into files.file_metadata (
    file_id,
    key,
    value
)
select
    f.file_id,
    'name',
    to_jsonb('Chatterbox Logo'::text)
from files.file f
where f.object_key = 'internal-assets/chatterbox-logo-color-bg.png'
on conflict (file_id, key) do nothing;

-- api: unauthenticated endpoint to fetch the app icon file id
create or replace function api.app_icon()
returns jsonb
language sql
stable
security definer
as $$
    select jsonb_build_object(
        'files',
        coalesce(jsonb_agg(f.file_id), '[]'::jsonb)
    )
    from files.file f
    where f.object_key = 'internal-assets/chatterbox-logo-color-bg.png';
$$;

grant execute on function api.app_icon() to anon, authenticated;

