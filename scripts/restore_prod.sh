#!/usr/bin/env bash
set -euo pipefail

# Restore a full logical dump into the prod DB
# Usage:
#   PROD_DATABASE_URL=postgres://... ./scripts/restore_prod.sh [dump_path] [jobs] [--reset-schema[=public]]
#   # or, if you only have DATABASE_URL set:
#   DATABASE_URL=postgres://... ./scripts/restore_prod.sh [dump_path] [jobs] [--reset-schema[=public]]
#
# Flags:
#   --reset-schema[=NAME]  Drop and recreate schema NAME (default: public) before restore.
#
# - dump_path: path to a .dump file from pg_dump -Fc (default: data/postgres/auction_dev.dump)
# - jobs: parallel jobs for pg_restore --jobs (default: 4)

DUMP_PATH="${1:-data/postgres/auction_dev.dump}"
JOBS="${2:-${JOBS:-4}}"

# Parse optional flags (supports being placed anywhere in args)
RESET_SCHEMA=""
for arg in "$@"; do
  case "$arg" in
    --reset-schema)
      RESET_SCHEMA="public"
      ;;
    --reset-schema=*)
      RESET_SCHEMA="${arg#*=}"
      ;;
  esac
done

# Rebuild positional args without recognized flags
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --reset-schema|--reset-schema=*) ;;
    *) POSITIONAL+=("$arg");;
  esac
done
set -- "${POSITIONAL[@]}"

# Re-evaluate positionals if provided
DUMP_PATH="${1:-$DUMP_PATH}"
JOBS="${2:-$JOBS}"

# Allow overriding client tool paths
PG_RESTORE_BIN="${PG_RESTORE_BIN:-pg_restore}"
PSQL_BIN="${PSQL_BIN:-psql}"

# Accept either PROD_DATABASE_URL or DATABASE_URL for convenience
TARGET_URL="${PROD_DATABASE_URL:-${DATABASE_URL:-}}"

if [[ -z "${TARGET_URL}" ]]; then
  echo "ERROR: neither PROD_DATABASE_URL nor DATABASE_URL is set" >&2
  echo "Usage: PROD_DATABASE_URL=postgres://... $0 [dump_path] [jobs]" >&2
  exit 1
fi

if [[ ! -f "$DUMP_PATH" ]]; then
  echo "ERROR: dump file not found: $DUMP_PATH" >&2
  exit 1
fi

echo "[restore_prod] Using URL=${TARGET_URL%%\?*}"
echo "[restore_prod] pg_restore: $PG_RESTORE_BIN"
echo "[restore_prod] Restoring from: $DUMP_PATH"
echo "[restore_prod] Parallel jobs: $JOBS"

# Optional: reset a schema before restore (clean slate)
if [[ -n "$RESET_SCHEMA" ]]; then
  echo "[restore_prod] Resetting schema '$RESET_SCHEMA' before restore (DROP SCHEMA ... CASCADE; CREATE SCHEMA)"
  "$PSQL_BIN" "$TARGET_URL" -v ON_ERROR_STOP=1 \
    -c "DROP SCHEMA IF EXISTS \"$RESET_SCHEMA\" CASCADE; CREATE SCHEMA \"$RESET_SCHEMA\";" || {
      echo "[restore_prod] ERROR: Failed to reset schema '$RESET_SCHEMA'" >&2
      exit 1
    }
  echo "[restore_prod] Schema '$RESET_SCHEMA' reset complete."
fi

# --clean/--if-exists drops objects first to align with dump state
# --no-owner/--no-privileges avoids ownership/GRANT issues across envs
"$PG_RESTORE_BIN" \
  --verbose \
  --clean --if-exists \
  --no-owner --no-privileges \
  --jobs="$JOBS" \
  --dbname "$TARGET_URL" \
  "$DUMP_PATH"

echo "[restore_prod] Done."
