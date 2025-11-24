-- ensure newly created accounts default to 'user' role

create or replace function accounts.create_account(
    _email text,
    _phone_number text,
    _password text,
    out validation_failure_message text,
    out created_account accounts.account
)
returns record
language plpgsql
security definer
as $$
declare
    _normalized_email text := accounts.normalize_email(_email);
    _normalized_phone_number text := accounts.normalize_phone(_phone_number);
begin
    if _normalized_email is null and _normalized_phone_number is null then
        validation_failure_message := 'email_or_phone_number_required';
        return;
    end if;

    if _normalized_email is not null and not accounts.is_email_valid(_normalized_email) then
        validation_failure_message := 'invalid_email';
        return;
    end if;

    if _normalized_phone_number is not null and not accounts.is_phone_valid(_normalized_phone_number) then
        validation_failure_message := 'invalid_phone_number';
        return;
    end if;

    if not accounts.is_password_valid_or_null(_password) then
        validation_failure_message := 'invalid_password';
        return;
    end if;

    if accounts.identifier_in_use(_normalized_email, _normalized_phone_number) then
        validation_failure_message := 'account_already_exists';
        return;
    end if;

    insert into accounts.account (email, phone_number, hashed_password)
    values (_normalized_email, _normalized_phone_number, crypt(_password, gen_salt('bf')))
    returning *
    into created_account;

    -- assign default 'user' role to the newly created account (idempotent)
    insert into accounts.account_role (account_id, role)
    values (created_account.account_id, 'user')
    on conflict (account_id, role) do nothing;

    return;
end;
$$;

