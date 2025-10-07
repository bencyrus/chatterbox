## Migrations and Secrets

Purpose

- Explain how to apply migrations with secret substitution and how to take/restore backups during development.

Migrations

- Migration files live in `postgres/migrations` and are applied in lexical order.
- Use the script `postgres/scripts/apply_migrations.sh` with `{secrets.*}` placeholder substitution.
- Placeholder mapping: `{secrets.secret_jwt_secret}` → env `JWT_SECRET` (strip leading `secret_`, uppercase).
- Required env: point `--secrets` to `secrets/.env.postgres` which provides the variables consumed by placeholders.

Examples

```bash
# Dry run
./postgres/scripts/apply_migrations.sh --db-url "$DATABASE_URL" --dry-run --verbose

# Apply all in a single transaction (default)
./postgres/scripts/apply_migrations.sh --db-url "$DATABASE_URL" --verbose

# Apply per-file (each migration in its own transaction)
./postgres/scripts/apply_migrations.sh --db-url "$DATABASE_URL" --per-file --verbose
```

Secrets files

- `secrets/.env.postgres`: consumed by migrations script and the Postgres container.
- `secrets/.env.postgrest`: used by the PostgREST container.
- `secrets/.env.gateway`, `secrets/.env.worker`, `secrets/.env.files`: service-specific env.

Backups

- Inside docker-compose, the Postgres container ships a `pg-backup` utility.
- Host wrapper: `./postgres/run-db-backup.sh` creates a full-cluster snapshot under `postgres/backups/cluster_*.sql.gz`.
- Restore from a saved snapshot:

```bash
./postgres/run-db-restore.sh cluster_YYYYMMDDTHHMMSSZ.sql.gz
```

Notes

- The `postgres/Dockerfile` installs `pg-backup` into the container and exposes `/backups` as a volume; compose mounts `./postgres/backups` there.
- PostgREST config must align with JWT secret and role settings from the migrations; see `postgres/README.md`.

## Navigate

- Back to Postgres: [Postgres Index](README.md)
