#!/usr/bin/env bash
set -euo pipefail

# Purpose: Always take a full-cluster snapshot (roles + all databases).
# Usage (from host): docker compose exec postgres pg-backup

DB_USER="${POSTGRES_USER:-postgres}"
BACKUP_DIR="/backups"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="${BACKUP_DIR}/cluster_${TIMESTAMP}.sql.gz"

mkdir -p "${BACKUP_DIR}"

echo "Creating full cluster snapshot as '${DB_USER}' -> ${OUT_FILE}"
pg_dumpall -U "${DB_USER}" | gzip -9 > "${OUT_FILE}"
echo "Backup complete: ${OUT_FILE}"

