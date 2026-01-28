-- Token use domain: defines the types of tokens that can be used
create domain auth.token_use as text
    check (value in ('access', 'refresh'));

-- JWT config function: retrieves the JWT config from the configuration table
create or replace function auth.jwt_config(
    out secret text,
    out access_token_expiry_seconds integer,
    out refresh_token_expiry_seconds integer
)
returns record
stable
language sql
security definer
as $$
    select
        (cfg->>'secret')::text,
        (cfg->>'access_token_expiry_seconds')::int,
        (cfg->>'refresh_token_expiry_seconds')::int
    from (select internal.get_config('jwt') as cfg) s;
$$;

-- Create access token function: creates an access token for an account
create or replace function auth.create_access_token(
    _account_id bigint,
    out access_token text
)
returns text
stable
language plpgsql
security definer
as
$$
declare
    _jwt_config record := auth.jwt_config();
begin
    access_token := auth.sign(
        jsonb_build_object(
            'sub', _account_id,
            'role', 'authenticated',
            'token_use', 'access'::auth.token_use,
            'iat', extract(epoch from now())::int,
            'nbf', extract(epoch from now())::int,
            'exp', extract(
                epoch from now() + make_interval(
                    secs => (_jwt_config.access_token_expiry_seconds)
                )
            )::int
        ),
        (_jwt_config.secret),
        'HS256'
    );

    return;
end;
$$;

-- Create refresh token function: creates a refresh token for an account
create or replace function auth.create_refresh_token(
    _account_id bigint,
    out refresh_token text
)
returns text
stable
language plpgsql
security definer
as $$
declare
    _jwt_config record := auth.jwt_config();
begin
    refresh_token := auth.sign(
        jsonb_build_object(
            'sub', _account_id,
            'role', 'authenticated',
            'token_use', 'refresh'::auth.token_use,
            'iat', extract(epoch from now())::int,
            'nbf', extract(epoch from now())::int,
            'exp', extract(
                epoch from now() + make_interval(
                    secs => (_jwt_config.refresh_token_expiry_seconds)
                )
            )::int
        ),
        (_jwt_config.secret),
        'HS256'
    );

    return;
end;
$$;

-- Validate token function: validates a token and returns the account_id
create or replace function auth.validate_token(
    _token text,
    _required_use auth.token_use,
    out validation_failure_message text,
    out account_id bigint
)
returns record
language plpgsql
security definer
as $$
declare
    _payload jsonb;
    _sub bigint;
    _token_use text;
    _jwt_config record := auth.jwt_config();
    _verify_result record;
begin
    _verify_result := auth.verify(_token, _jwt_config.secret, 'HS256');
    if not _verify_result.valid then
        validation_failure_message := 'token_invalid';
        return;
    end if;

    _payload := _verify_result.payload;

    _sub := (_payload->>'sub')::bigint;
    _token_use := _payload->>'token_use';
    if _required_use is not null and _token_use is distinct from _required_use then
        validation_failure_message := 'wrong_token_use';
        return;
    end if;

    account_id := _sub;
    return;
end;
$$;
