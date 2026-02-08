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

**Deploy with fresh database and apply migrations (WARNING: destroys data):**
```bash
make prod-fresh-detached
```

**Deploy with clean database without migrations:**
```bash
make prod-fresh-no-migrations
```
Useful when you want to restore from a backup instead of running migrations.

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

**Fresh start with clean database and migrations applied:**
```bash
make local-fresh
```

**Fresh start without migrations:**
```bash
make local-fresh-no-migrations
```
Useful when you want to restore from a prod backup instead of running migrations.

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

**Verify automated backups are working:**
```bash
# Check backup service logs (production only)
docker logs db-backup

# List all backups in GCS
gsutil ls -l gs://chatterbox-bucket-main/backups/postgres/
```

**Manual backup (local development):**
```bash
./postgres/run-db-backup.sh
```

The backup will be created in `./postgres/backups/cluster_YYYYMMDDTHHMMSSZ.sql.gz`.

---

### Restore Database (Two-Step Process)

Restoring a database backup requires two steps:
1. **Download** the backup from GCS to local disk
2. **Restore** the backup to your target database (local or prod)

#### Restore Latest Backup to Local

```bash
# Step 1: Download latest backup from GCS
make download-db-latest

# Step 2: Restore to local database
make local-restore-db-latest
```

#### Restore Specific Backup to Local

```bash
# Step 1: Download specific backup from GCS
make download-db-backup BACKUP=cluster_20260208T060000Z.sql.gz

# Step 2: Restore to local database
make local-restore-db-backup BACKUP=cluster_20260208T060000Z.sql.gz
```

#### Restore Latest Backup to Production (Disaster Recovery)

```bash
# Step 1: Download latest backup from GCS
make download-db-latest

# Step 2: Restore to production database
make prod-restore-db-latest
```

#### Restore Specific Backup to Production

```bash
# Step 1: Download specific backup from GCS
make download-db-backup BACKUP=cluster_20260208T060000Z.sql.gz

# Step 2: Restore to production database
make prod-restore-db-backup BACKUP=cluster_20260208T060000Z.sql.gz
```

**Why two steps?** 
- Download is the same operation regardless of target (fetches from GCS to `./postgres/backups/`)
- Restore is environment-specific (applies to local DB vs prod DB)
- This separation gives you control to inspect/verify the backup before restoring

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
