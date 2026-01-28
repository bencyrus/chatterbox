-- account file helpers: bridge between files and accounts
-- used by account deletion to find files owned by an account

-- helper: list non-deleted learning-related files for an account
create or replace function files.account_learning_files(
    _account_id bigint
)
returns setof files.file
language sql
stable
as $$
    select distinct f.*
    from files.file f
    join learning.profile_cue_recording pcr
        on pcr.file_id = f.file_id
    join learning.profile p
        on p.profile_id = pcr.profile_id
    where p.account_id = _account_id
      and not files.is_file_deleted(f.file_id);
$$;

-- helper: list non-deleted files associated with an account
create or replace function files.account_files(
    _account_id bigint
)
returns setof files.file
language sql
stable
as $$
    select *
    from files.account_learning_files(_account_id);
    -- future: union other account-owned file sources here
    -- union all
    -- select * from files.account_avatar_files(_account_id);
$$;
