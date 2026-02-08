## Backups and Restore

Status: current
Last verified: 2025-10-08

← Back to [`docs/deploy/README.md`](./README.md)

### Why this exists

- Provide simple, reliable scripts for full‑cluster logical backups and restores during development and basic deployments.
- Automated scheduled backups with GCS upload for production disaster recovery.

### How it works

#### Automated backups (production)

The `db-backup` service runs as a sidecar container that:

1. Connects to the `postgres` service over the compose network
2. Runs `pg_dumpall` on a configurable cron schedule (default: twice daily at 06:00 and 18:00 UTC / 1:00 AM and 1:00 PM EST)
3. Creates a temporary gzipped dump in `/backups` (mounted from `./postgres/backups/` on the host)
4. Uploads the dump to GCS at `gs://<bucket>/<prefix>/cluster_YYYYMMDDTHHMMSSZ.sql.gz`
5. Deletes the local backup immediately after successful upload (backups only live in GCS)

The sidecar runs one immediate backup on startup, then continues on schedule.

**Configuration:** [`secrets/.env.db-backup`](../../secrets/.env.db-backup.example)

The backup service connects as a dedicated `backup_service_user` database user (created via [`1756076000_backup_service_user.sql`](../../postgres/migrations/1756076000_backup_service_user.sql), like `worker_service_user` and `file_service_user`). Setup:

1. Define `BACKUP_SERVICE_USER_PASSWORD` in [`secrets/.env.postgres`](../../secrets/.env.postgres.example)
2. Run migrations to create the user (has `pg_read_all_data` and `pg_read_all_settings` for pg_dumpall)
3. Configure `DATABASE_URL` in [`secrets/.env.db-backup`](../../secrets/.env.db-backup.example)

Key settings:
- `DATABASE_URL`: Postgres connection string (uses `backup_service_user`)
- `BACKUP_SCHEDULE`: Cron expression (default `0 6,18 * * *` for twice daily at 1am and 1pm EST)
- `GCS_BACKUP_BUCKET` and `GCS_BACKUP_PREFIX`: GCS destination
- GCS service account credentials (same as files service)

**Note:** Local backups are deleted immediately after successful upload to GCS. The `./postgres/backups/` directory is only used as a temporary staging area during backup creation and upload.

**GCS retention:** Set a bucket lifecycle rule to auto-delete old backups (recommended 30-90 days):

```bash
gsutil lifecycle set /dev/stdin gs://YOUR_BUCKET <<'EOF'
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {
        "age": 30,
        "matchesPrefix": ["backups/postgres/"]
      }
    }
  ]
}
EOF
```

This rule only affects objects under the `backups/postgres/` prefix.

#### Manual backups (development)

- Container utility: [`postgres/scripts/pg-backup.sh`](../../postgres/scripts/pg-backup.sh)
  - Runs `pg_dumpall -U "$POSTGRES_USER" | gzip -9` and writes `/backups/cluster_YYYYMMDDTHHMMSSZ.sql.gz` inside the container.
- Host backup wrapper: [`postgres/run-db-backup.sh`](../../postgres/run-db-backup.sh)
  - Invokes the container utility and surfaces the created file under `./postgres/backups/` on the host.

### Operations

#### Create a manual backup

```bash
./postgres/run-db-backup.sh
```

#### Restore from GCS (Two-Step Process)

Restoring from GCS requires two steps: download, then restore.

**Option 1: Using Make targets (Recommended)**

Restore latest backup to local:
```bash
make download-db-latest
make local-restore-db-latest
```

Restore specific backup to local:
```bash
make download-db-backup BACKUP=cluster_20260208T060000Z.sql.gz
make local-restore-db-backup BACKUP=cluster_20260208T060000Z.sql.gz
```

Restore latest backup to production (disaster recovery):
```bash
make download-db-latest
make prod-restore-db-latest
```

Restore specific backup to production:
```bash
make download-db-backup BACKUP=cluster_20260208T060000Z.sql.gz
make prod-restore-db-backup BACKUP=cluster_20260208T060000Z.sql.gz
```

**Option 2: Using scripts directly**

1. Download the backup from GCS:

   ```bash
   gsutil cp gs://chatterbox-bucket-main/backups/postgres/cluster_YYYYMMDDTHHMMSSZ.sql.gz ./postgres/backups/
   ```

2. Restore using the standard script:

   ```bash
   ./postgres/run-db-restore.sh cluster_YYYYMMDDTHHMMSSZ.sql.gz
   ```

**Note:** The restore script affects the database on the machine where you run it (local vs prod).

#### List available GCS backups

```bash
gsutil ls gs://chatterbox-bucket-main/backups/postgres/
```

### Notes

- Backups are logical SQL dumps (roles + all databases); files are stored under `postgres/backups/` on the host (mounted to `/backups` in containers).
- Restores apply SQL into the running Postgres; they do not wipe volumes.
- The automated backup service logs all operations via the centralized logger (visible in Datadog when observability profile is active).
- For best disaster recovery, verify restores periodically by testing on a separate environment.

### See also

- Deploy overview: [`./README.md`](./README.md)
- Runtime topology: [`./runtime-topology.md`](./runtime-topology.md)
