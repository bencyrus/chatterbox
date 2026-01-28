-- comms schema
create schema comms;
grant usage on schema comms to worker_service_user;

create or replace function comms.from_email_address(
    _key text
)
returns text
stable
language sql
as $$
    select (internal.get_config('from_emails') ->> _key)::text;
$$;

-- domain for communication channel kinds
create domain comms.channel as text
    check (value in ('email', 'sms'));

-- base message table
create table comms.message (
    message_id bigserial primary key,
    channel comms.channel not null,
    created_at timestamp with time zone not null default now()
);

-- email payload table
create table comms.email_message (
    message_id bigint primary key references comms.message(message_id) on delete cascade,
    from_address text not null,
    to_address text not null,
    subject text not null,
    html text not null
);

-- sms payload table
create table comms.sms_message (
    message_id bigint primary key references comms.message(message_id) on delete cascade,
    to_number text not null,
    body text not null
);

create or replace function comms.create_email_message(
    _from_address text,
    _to_address text,
    _subject text,
    _html text,
    out validation_failure_message text,
    out created_message_id bigint
)
language plpgsql
security definer
as $$
begin
    if _from_address is null then
        validation_failure_message := 'from_address_missing';
        return;
    end if;
    if _to_address is null then
        validation_failure_message := 'to_address_missing';
        return;
    end if;
    if _subject is null then
        validation_failure_message := 'subject_missing';
        return;
    end if;
    if _html is null then
        validation_failure_message := 'html_missing';
        return;
    end if;

    insert into comms.message (channel)
    values ('email')
    returning message_id
    into created_message_id;
    
    insert into comms.email_message (message_id, from_address, to_address, subject, html)
    values (created_message_id, _from_address, _to_address, _subject, _html);
    return;
end;
$$;

create or replace function comms.create_sms_message(
    _to_number text,
    _body text,
    out validation_failure_message text,
    out created_message_id bigint
)
language plpgsql
security definer
as $$
begin
    if _to_number is null then
        validation_failure_message := 'to_number_missing';
        return;
    end if;
    if _body is null then
        validation_failure_message := 'body_missing';
        return;
    end if;

    insert into comms.message (channel)
    values ('sms')
    returning message_id
    into created_message_id;

    insert into comms.sms_message (message_id, to_number, body)
    values (created_message_id, _to_number, _body);
    return;
end;
$$;

create or replace function comms.message_exists(
    _message_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from comms.message m
        where m.message_id = _message_id
    );
$$;
