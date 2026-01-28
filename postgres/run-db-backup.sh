#!/usr/bin/env bash
set -euo pipefail

# Host wrapper: create a full-cluster snapshot via the postgres container.
# Output files are written under ./postgres/backups

echo "Creating full cluster backup inside container..."
docker compose exec postgres pg-backup

LATEST=$(ls -1t "$(dirname "$0")/backups"/cluster_*.sql.gz 2>/dev/null | head -1 || true)
if [[ -n "${LATEST}" ]]; then
  echo "Backup complete: ${LATEST}"
else
  echo "No cluster backup found in ./postgres/backups (check container logs)." >&2
  exit 1
fi
