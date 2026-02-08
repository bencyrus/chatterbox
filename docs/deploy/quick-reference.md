# Quick Reference

Common operations for deploying and managing Chatterbox.

---

## Deploy to Production

**Prerequisites:**
- Create all required secrets files in `secrets/` (copy from `.example` files)
- Ensure `.env.postgres`, `.env.gateway`, `.env.worker`, `.env.files`, `.env.caddy`, `.env.db-backup` exist with real values

**Deploy in background:**
```bash
make prod-up-detached
```

**Deploy with fresh database (WARNING: destroys data):**
```bash
make prod-fresh-detached
```

**Deploy and watch all logs in real-time:**
```bash
make prod-up
```
---


### Local Development

**Start everything (with hot reload):**
```bash
make local-up
```

**Fresh start with clean database:**
```bash
make local-fresh
```

**Run in background:**
```bash
make local-up-detached
```

---

### Apply Migrations

**Apply all migrations:**
```bash
MIGRATIONS_ENV=prod make migrate
```

**Apply a specific migration only:**
```bash
MIGRATIONS_ENV=prod make migrate ARGS="--only 1756076000_backup_service_user"
```

**Per-file transaction mode:**
```bash
MIGRATIONS_ENV=prod make migrate ARGS="--per-file"
```

By default, all migrations run in a single transaction (safest - rolls back everything if any migration fails). Use `--per-file` to run each migration file in its own transaction.

To apply to local db, just set `local` as the `MIGRATIONS_ENV` value and run the same command:

**For local development:**
```bash
MIGRATIONS_ENV=local make migrate
```

---

### Database Backups

**Verify backups are working:**
```bash
# Check logs
docker logs db-backup

# List backups in GCS
gsutil ls -l gs://YOUR_BUCKET/backups/postgres/
```

**Manual backup:**
```bash
./postgres/run-db-backup.sh
```

The backup will be created in `./postgres/backups/cluster_YYYYMMDDTHHMMSSZ.sql.gz`.

**Restore from GCS:**
```bash
# Download the backup file from GCP to the server
gsutil cp gs://YOUR_BUCKET/backups/postgres/cluster_20260208T050000Z.sql.gz ./postgres/backups/

# Restore to the local running database (wherever you run this command)
./postgres/run-db-restore.sh cluster_20260208T050000Z.sql.gz
```

**IMPORTANT:** The restore script affects the database on the machine where you run it:
- Run on production VM → restores to production database
- Run on local machine → restores to local database

---

### Stop Everything

**Stop production services:**
```bash
make down
```

**Stop and remove volumes (WARNING: destroys data):**
```bash
make down-volumes
```

**Stop local services:**
```bash
make local-down              # Stop only
make local-down-volumes      # Stop and remove volumes
```
