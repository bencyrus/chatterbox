#!/usr/bin/env bash
set -euo pipefail

# Host wrapper: restore cluster from a backup file under ./postgres/backups.
# Usage: ./postgres/run-db-restore.sh cluster_YYYYMMDDTHHMMSSZ.sql.gz

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUPS_DIR="${SCRIPT_DIR}/backups"

if [[ $# -lt 1 ]]; then
  echo "Error: missing backup name." >&2
  echo "Usage: $0 <backup-filename-in-postgres/backups>" >&2
  AVAIL=$(ls -1 "${BACKUPS_DIR}"/cluster_*.sql.gz 2>/dev/null | sed -E 's|.*/||' | head -5 || true)
  if [[ -n "${AVAIL}" ]]; then
    echo "Available backups (top 5):" >&2
    echo "${AVAIL}" >&2
  else
    echo "No backups found in ${BACKUPS_DIR}." >&2
  fi
  exit 1
fi

BACKUP_NAME="$1"
BACKUP_FILE="${BACKUPS_DIR}/${BACKUP_NAME}"

if [[ ! -f "${BACKUP_FILE}" ]]; then
  echo "Backup not found: ${BACKUP_FILE}" >&2
  AVAIL=$(ls -1 "${BACKUPS_DIR}"/cluster_*.sql.gz 2>/dev/null | sed -E 's|.*/||' | head -5 || true)
  if [[ -n "${AVAIL}" ]]; then
    echo "Available backups (top 5):" >&2
    echo "${AVAIL}" >&2
  fi
  exit 1
fi

echo "Restoring cluster from ${BACKUP_FILE} (no volume wipe) ..."
gunzip -c "${BACKUP_FILE}" | docker compose exec -T postgres sh -lc 'psql -U "$POSTGRES_USER" -d postgres'

echo "Restore complete."
