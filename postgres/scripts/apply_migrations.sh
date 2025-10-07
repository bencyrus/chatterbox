#!/usr/bin/env bash
set -euo pipefail

# Apply Postgres migrations with {secrets.*} substitution.
# Mapping rule: {secrets.secret_jwt_secret} -> env JWT_SECRET (strip leading 'secret_', uppercase)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

DEFAULT_MIGRATIONS_DIR="${REPO_ROOT}/postgres/migrations"
DEFAULT_SECRETS_FILE="${REPO_ROOT}/secrets/.env.postgres"
PSQL_BIN="psql"
DB_URL="${DATABASE_URL:-}"
MIGRATIONS_DIR="${DEFAULT_MIGRATIONS_DIR}"
SECRETS_FILE="${DEFAULT_SECRETS_FILE}"
DRY_RUN=0
VERBOSE=0
SINGLE_TX=1

usage() {
  cat <<EOF
Usage: $0 [--db-url URL] [--migrations DIR] [--secrets FILE] [--psql PATH] [--dry-run] [--single-transaction|--per-file] [--verbose]

Options:
  --db-url URL      Postgres database URL (or set DATABASE_URL)
  --migrations DIR  Directory containing migration .sql files (default: ${DEFAULT_MIGRATIONS_DIR})
  --secrets FILE    Path to secrets .env.postgres (default: ${DEFAULT_SECRETS_FILE})
  --psql PATH       Path to psql binary (default: psql)
  --dry-run         Validate and list migrations without applying
  --single-transaction
                    Run all migrations in one transaction (default)
  --per-file        Run each migration file in its own transaction
  --verbose         Verbose logging
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-url)
      DB_URL="$2"; shift 2;;
    --migrations)
      MIGRATIONS_DIR="$2"; shift 2;;
    --secrets)
      SECRETS_FILE="$2"; shift 2;;
    --psql)
      PSQL_BIN="$2"; shift 2;;
    --dry-run)
      DRY_RUN=1; shift;;
    --single-transaction)
      SINGLE_TX=1; shift;;
    --per-file)
      SINGLE_TX=0; shift;;
    --verbose)
      VERBOSE=1; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "${DB_URL}" ]]; then
  echo "Error: --db-url not provided and DATABASE_URL not set" >&2
  exit 2
fi

if [[ ! -d "${MIGRATIONS_DIR}" ]]; then
  echo "Error: migrations directory not found: ${MIGRATIONS_DIR}" >&2
  exit 2
fi

if [[ ! -f "${SECRETS_FILE}" ]]; then
  echo "Error: secrets file not found: ${SECRETS_FILE}" >&2
  exit 2
fi

[[ ${VERBOSE} -eq 1 ]] && echo "Loading secrets from ${SECRETS_FILE}"

# Load secrets into environment
set -a
source "${SECRETS_FILE}"
set +a

# List and sort .sql files (portable across macOS Bash 3.2)
MIG_LIST_FILE=$(mktemp "${TMPDIR:-/tmp}/migr_list.XXXXXX")
if ! find "${MIGRATIONS_DIR}" -maxdepth 1 -type f -name '*.sql' -print | sort > "${MIG_LIST_FILE}"; then
  echo "Failed to enumerate migration files" >&2
  rm -f "${MIG_LIST_FILE}"
  exit 2
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

  if [[ ${DRY_RUN} -eq 1 ]]; then
    [[ ${VERBOSE} -eq 1 ]] && echo "Validated ${label}"
    rm -f "${tmpfile}"
    return 0
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

  if [[ ${DRY_RUN} -eq 1 ]]; then
    [[ ${VERBOSE} -eq 1 ]] && echo "Validated combined migration plan"
    rm -f "${COMBINED_SQL}" "${MIG_LIST_FILE}"
    exit 0
  fi

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

