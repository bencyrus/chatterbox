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
2. Runs `pg_dumpall` on a configurable cron schedule (default: twice daily at 02:00 and 14:00 UTC)
3. Writes gzipped dumps to `./postgres/backups/` on the host
4. Uploads each dump to GCS at `gs://<bucket>/<prefix>/cluster_YYYYMMDDTHHMMSSZ.sql.gz`
5. Cleans up local files older than the configured retention period (default: 3 days)

The sidecar runs one immediate backup on startup, then continues on schedule.

**Configuration:** [`secrets/.env.db-backup`](../../secrets/.env.db-backup.example)

Key settings:
- `BACKUP_SCHEDULE`: Cron expression (default `0 2,14 * * *` for twice daily)
- `LOCAL_RETENTION_DAYS`: How long to keep local backups (default `3`)
- `GCS_BACKUP_BUCKET` and `GCS_BACKUP_PREFIX`: GCS destination
- GCS service account credentials (same as files service)

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

#### Restore from a local backup

```bash
./postgres/run-db-restore.sh cluster_YYYYMMDDTHHMMSSZ.sql.gz
```

#### Restore from GCS (disaster recovery)

1. Download the backup from GCS:

   ```bash
   gsutil cp gs://YOUR_BUCKET/backups/postgres/cluster_YYYYMMDDTHHMMSSZ.sql.gz ./postgres/backups/
   ```

2. Restore using the standard script:

   ```bash
   ./postgres/run-db-restore.sh cluster_YYYYMMDDTHHMMSSZ.sql.gz
   ```

#### List available GCS backups

```bash
gsutil ls gs://YOUR_BUCKET/backups/postgres/
```

### Notes

- Backups are logical SQL dumps (roles + all databases); files are stored under `postgres/backups/` on the host (mounted to `/backups` in containers).
- Restores apply SQL into the running Postgres; they do not wipe volumes.
- The automated backup service logs all operations via the centralized logger (visible in Datadog when observability profile is active).
- For best disaster recovery, verify restores periodically by testing on a separate environment.

### See also

- Deploy overview: [`./README.md`](./README.md)
- Runtime topology: [`./runtime-topology.md`](./runtime-topology.md)
