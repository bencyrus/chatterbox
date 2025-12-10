#!/usr/bin/env bash
set -euo pipefail

# Apply Postgres migrations with {secrets.*} substitution.
# Mapping rule: {secrets.secret_jwt_secret} -> env JWT_SECRET (strip leading 'secret_', uppercase)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

DEFAULT_MIGRATIONS_DIR="${REPO_ROOT}/postgres/migrations"
PSQL_BIN="psql"
DB_URL=""
MIGRATIONS_DIR="${DEFAULT_MIGRATIONS_DIR}"
SECRETS_FILE=""
VERBOSE=0
SINGLE_TX=1

usage() {
  cat <<EOF
Usage: $0 [--verbose|-v] [--per-file] [--only <migration.sql>]

Options:
  --verbose, -v     Verbose logging
  --per-file        Run each migration file in its own transaction (default is single transaction)
  --only NAME       Apply only the specified migration (basename, basename without .sql, or path)

Examples:
  $0 --only 1756074400_magic_link_login
  $0 --per-file --verbose
EOF
}

MIG_ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --per-file)
      SINGLE_TX=0
      shift
      ;;
    --verbose|-v)
      VERBOSE=1
      shift
      ;;
    --only)
      if [[ $# -lt 2 ]]; then
        echo "--only requires a filename" >&2
        exit 2
      fi
      MIG_ONLY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Require MIGRATIONS_ENV to select the secrets file (e.g. local|prod).
if [[ -z "${MIGRATIONS_ENV:-}" ]]; then
  echo "Error: MIGRATIONS_ENV is required (e.g. MIGRATIONS_ENV=local or MIGRATIONS_ENV=prod)" >&2
  exit 2
fi

case "${MIGRATIONS_ENV}" in
  local)
    SECRETS_FILE="${REPO_ROOT}/secrets/.env.postgres.local" ;;
  prod)
    SECRETS_FILE="${REPO_ROOT}/secrets/.env.postgres" ;;
  *)
    echo "Error: unknown MIGRATIONS_ENV='${MIGRATIONS_ENV}'. Expected 'local' or 'prod'." >&2
    exit 2 ;;
esac

if [[ ! -d "${MIGRATIONS_DIR}" ]]; then
  echo "Error: migrations directory not found: ${MIGRATIONS_DIR}" >&2
  exit 2
fi

if [[ ! -f "${SECRETS_FILE}" ]]; then
  echo "Error: secrets file not found: ${SECRETS_FILE}" >&2
  exit 2
fi

[[ ${VERBOSE} -eq 1 ]] && echo "Loading secrets from ${SECRETS_FILE}"
set -a
# shellcheck source=/dev/null
source "${SECRETS_FILE}"
set +a

# Always build DATABASE_URL from POSTGRES_* values
POSTGRES_SSL_MODE="${POSTGRES_SSL_MODE:-disable}"
missing=()
for v in POSTGRES_HOST POSTGRES_PORT POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    missing+=("$v")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: missing required env vars: ${missing[*]}" >&2
  exit 2
fi
DB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=${POSTGRES_SSL_MODE}"
[[ ${VERBOSE} -eq 1 ]] && echo "Constructed DATABASE_URL from POSTGRES_* env vars."

# Build migration list (all or a single file)
MIG_LIST_FILE=$(mktemp "${TMPDIR:-/tmp}/migr_list.XXXXXX")
if [[ -n "${MIG_ONLY}" ]]; then
  # Resolve path: allow basename under MIGRATIONS_DIR or explicit path
  CANDIDATE="${MIG_ONLY}"
  if [[ ! -f "${CANDIDATE}" ]]; then
    # If NAME has no .sql, try adding it
    if [[ "${MIG_ONLY}" != *.sql ]]; then
      if [[ -f "${MIGRATIONS_DIR}/${MIG_ONLY}.sql" ]]; then
        CANDIDATE="${MIGRATIONS_DIR}/${MIG_ONLY}.sql"
      else
        CANDIDATE="${MIGRATIONS_DIR}/${MIG_ONLY}"
      fi
    else
      CANDIDATE="${MIGRATIONS_DIR}/${MIG_ONLY}"
    fi
  fi
  if [[ ! -f "${CANDIDATE}" ]]; then
    echo "Migration not found: ${MIG_ONLY}" >&2
    rm -f "${MIG_LIST_FILE}"
    exit 2
  fi
  printf '%s
' "${CANDIDATE}" > "${MIG_LIST_FILE}"
else
  if ! find "${MIGRATIONS_DIR}" -maxdepth 1 -type f -name '*.sql' -print | sort > "${MIG_LIST_FILE}"; then
    echo "Failed to enumerate migration files" >&2
    rm -f "${MIG_LIST_FILE}"
    exit 2
  fi
fi

NUM_FILES=$(wc -l < "${MIG_LIST_FILE}" | tr -d ' ')
if [[ "${NUM_FILES}" == "0" ]]; then
  echo "No .sql files found in ${MIGRATIONS_DIR}"
  rm -f "${MIG_LIST_FILE}"
  exit 0
fi

[[ ${VERBOSE} -eq 1 ]] && {
  echo "Found ${NUM_FILES} migration(s):"
  while IFS= read -r f; do echo " - $(basename "$f")"; done < "${MIG_LIST_FILE}"
}

substitute_and_apply() {
  local input_sql="$1"
  local label
  label="$(basename "${input_sql}")"
  [[ ${VERBOSE} -eq 1 ]] && echo "Processing ${label}..."

  local tmpfile
  tmpfile=$(mktemp "${TMPDIR:-/tmp}/migr.XXXXXX.sql")

  # Perl performs the placeholder substitution using the environment map.
  # {secrets.token} -> strip leading 'secret_' then uppercase to get env var
  if ! perl -0777 -pe '
    s#\{secrets\.([A-Za-z0-9_]+)\}# do {
      my $k = $1;
      $k =~ s/^secret_//;
      my $env = uc($k);
      die "Missing secret env: $env\n" unless exists $ENV{$env};
      $ENV{$env}
    } #ge;
  ' "${input_sql}" > "${tmpfile}"; then
    echo "Error while preparing ${label}" >&2
    rm -f "${tmpfile}"
    exit 1
  fi

  local -a cmd
  cmd=("${PSQL_BIN}" --dbname "${DB_URL}" -v ON_ERROR_STOP=1 -f "${tmpfile}")
  [[ ${VERBOSE} -eq 1 ]] && printf 'Executing: %q ' "${cmd[@]}" && echo
  if ! "${cmd[@]}"; then
    echo "psql failed for ${label}" >&2
    rm -f "${tmpfile}"
    exit 1
  fi
  rm -f "${tmpfile}"
}

if [[ ${SINGLE_TX} -eq 1 ]]; then
  [[ ${VERBOSE} -eq 1 ]] && echo "Running all migrations in a single transaction..."
  COMBINED_SQL=$(mktemp "${TMPDIR:-/tmp}/migr_combined.XXXXXX.sql")
  echo "begin;" > "${COMBINED_SQL}"

  while IFS= read -r sql; do
    label="$(basename "${sql}")"
    [[ ${VERBOSE} -eq 1 ]] && echo "Processing ${label}..."
    # Substitute placeholders, then strip standalone BEGIN/COMMIT lines
    if ! perl -0777 -pe '
      s#\{secrets\.([A-Za-z0-9_]+)\}# do {
        my $k = $1;
        $k =~ s/^secret_//;
        my $env = uc($k);
        die "Missing secret env: $env\n" unless exists $ENV{$env};
        $ENV{$env}
      } #ge;
    ' "${sql}" | perl -ne 'print unless /^[ \t]*(?i:begin|commit);[ \t]*$/;' >> "${COMBINED_SQL}"; then
      echo "Error while preparing ${label}" >&2
      rm -f "${COMBINED_SQL}" "${MIG_LIST_FILE}"
      exit 1
    fi
    echo >> "${COMBINED_SQL}"
  done < "${MIG_LIST_FILE}"

  echo "commit;" >> "${COMBINED_SQL}"

  cmd=("${PSQL_BIN}" --dbname "${DB_URL}" -v ON_ERROR_STOP=1 -f "${COMBINED_SQL}")
  [[ ${VERBOSE} -eq 1 ]] && printf 'Executing: %q ' "${cmd[@]}" && echo
  if ! "${cmd[@]}"; then
    echo "psql failed for combined migration" >&2
    rm -f "${COMBINED_SQL}" "${MIG_LIST_FILE}"
    exit 1
  fi
  rm -f "${COMBINED_SQL}" "${MIG_LIST_FILE}"
  [[ ${VERBOSE} -eq 1 ]] && echo "All migrations applied successfully."
else
  while IFS= read -r sql; do
    substitute_and_apply "${sql}"
  done < "${MIG_LIST_FILE}"

  rm -f "${MIG_LIST_FILE}"

  [[ ${VERBOSE} -eq 1 ]] && echo "All migrations applied successfully."
fi

exit 0
