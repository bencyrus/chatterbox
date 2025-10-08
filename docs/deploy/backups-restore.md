## Backups and Restore

Status: current
Last verified: 2025-10-08

← Back to [`docs/deploy/README.md`](./README.md)

### Why this exists

- Provide simple, reliable scripts for full‑cluster logical backups and restores during development and basic deployments.

### How it works

- Container utility: [`postgres/scripts/pg-backup.sh`](../../postgres/scripts/pg-backup.sh)
  - Runs `pg_dumpall -U "$POSTGRES_USER" | gzip -9` and writes `/backups/cluster_YYYYMMDDTHHMMSSZ.sql.gz` inside the container.
- Host backup wrapper: [`postgres/run-db-backup.sh`](../../postgres/run-db-backup.sh)
  - Invokes the container utility and surfaces the created file under `./postgres/backups/` on the host.
- Host restore wrapper: [`postgres/run-db-restore.sh`](../../postgres/run-db-restore.sh)
  - Streams a selected `cluster_*.sql.gz` file into `psql` inside the running Postgres container.

### Operations

- Create a backup

  ```bash
  ./postgres/run-db-backup.sh
  ```

- Restore from a backup

  ```bash
  ./postgres/run-db-restore.sh cluster_YYYYMMDDTHHMMSSZ.sql.gz
  ```

### Notes

- Backups are logical SQL dumps (roles + all databases); files are stored under `postgres/backups/` on the host (mounted to `/backups` in the container).
- Restores apply SQL into the running Postgres; they do not wipe volumes.

### See also

- Deploy overview: [`./README.md`](./README.md)
- Runtime topology: [`./runtime-topology.md`](./runtime-topology.md)
