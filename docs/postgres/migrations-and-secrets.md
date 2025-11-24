## Migrations and Secrets

Status: current
Last verified: 2025-10-08

← Back to [`docs/postgres/README.md`](./README.md)

### Why this exists

- Explain how to apply migrations with secret substitution and how to take/restore backups during development.

### Migrations

- Migration files live in `postgres/migrations` and are applied in lexical order.
- Use the script `postgres/scripts/apply_migrations.sh` with `{secrets.*}` placeholder substitution.
- Placeholder mapping: `{secrets.secret_jwt_secret}` → env `JWT_SECRET` (strip leading `secret_`, uppercase).
- Secrets are loaded automatically from `secrets/.env.postgres` (this file must exist before you run the script).

### Examples

```bash
# Apply all migrations in a single transaction (default)
./postgres/scripts/apply_migrations.sh

# Apply all migrations with verbose logging
./postgres/scripts/apply_migrations.sh --verbose

# Apply each migration file in its own transaction
./postgres/scripts/apply_migrations.sh --per-file

# Apply only one migration file by name (with or without .sql)
./postgres/scripts/apply_migrations.sh --only 1756074400_magic_link_login
```

### Secrets files

- `secrets/.env.postgres`: consumed by migrations script and the Postgres container.
- `secrets/.env.postgrest`: used by the PostgREST container.
- `secrets/.env.gateway`, `secrets/.env.worker`, `secrets/.env.files`: service-specific env.

### Backups

- Inside docker-compose, the Postgres container ships a `pg-backup` utility.
- Host wrapper: `./postgres/run-db-backup.sh` creates a full-cluster snapshot under `postgres/backups/cluster_*.sql.gz`.
- Restore from a saved snapshot:

```bash
./postgres/run-db-restore.sh cluster_YYYYMMDDTHHMMSSZ.sql.gz
```

### Notes

- The `postgres/Dockerfile` installs `pg-backup` into the container and exposes `/backups` as a volume; compose mounts `./postgres/backups` there.
- PostgREST config must align with JWT secret and role settings from the migrations; see `postgres/README.md`.

### Environment variable mappings (used by migrations)

- Provided via `secrets/.env.postgres` (consumed by `apply_migrations.sh` and the Postgres container):
  - `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `PGTZ`
  - `AUTHENTICATOR_PASSWORD` → used by `1756072100_setup.sql` to set the `authenticator` role password
  - `JWT_SECRET` → seeded by `1756072325_config_setup.sql` into `internal.config('jwt')`
  - `HELLO_EMAIL`, `NOREPLY_EMAIL` → seeded by `1756072325_config_setup.sql` into `internal.config('from_emails')`

### See also

- Back to Postgres: [Postgres Index](README.md)
