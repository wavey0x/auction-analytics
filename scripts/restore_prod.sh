#!/usr/bin/env bash
set -euo pipefail

# Restore a full logical dump into the prod DB
# Usage:
#   PROD_DATABASE_URL=postgres://... ./scripts/restore_prod.sh [dump_path] [jobs]
#
# - dump_path: path to a .dump file from pg_dump -Fc (default: data/postgres/auction_dev.dump)
# - jobs: parallel jobs for pg_restore --jobs (default: 4)

DUMP_PATH="${1:-data/postgres/auction_dev.dump}"
JOBS="${2:-${JOBS:-4}}"

if [[ -z "${PROD_DATABASE_URL:-}" ]]; then
  echo "ERROR: PROD_DATABASE_URL is not set" >&2
  exit 1
fi

if [[ ! -f "$DUMP_PATH" ]]; then
  echo "ERROR: dump file not found: $DUMP_PATH" >&2
  exit 1
fi

echo "[restore_prod] Using PROD_DATABASE_URL=${PROD_DATABASE_URL%%\?*}"
echo "[restore_prod] Restoring from: $DUMP_PATH"
echo "[restore_prod] Parallel jobs: $JOBS"

# --clean/--if-exists drops objects first to align with dump state
# --no-owner/--no-privileges avoids ownership/GRANT issues across envs
pg_restore \
  --verbose \
  --clean --if-exists \
  --no-owner --no-privileges \
  --jobs="$JOBS" \
  --dbname "$PROD_DATABASE_URL" \
  "$DUMP_PATH"

echo "[restore_prod] Done."

