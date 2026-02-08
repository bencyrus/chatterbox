-- backup service user for pg_dumpall
-- Note: pg_dumpall requires elevated privileges to dump global objects (roles, tablespaces, etc.)
-- We grant pg_read_all_settings and pg_read_all_data for comprehensive read access.
create user backup_service_user with login password '{secrets.backup_service_user_password}';

-- Grant read access to all data and settings (required for pg_dumpall)
grant pg_read_all_settings to backup_service_user;
grant pg_read_all_data to backup_service_user;

-- Allow connecting to all databases (required for pg_dumpall)
-- Note: This user can read but not modify any data
