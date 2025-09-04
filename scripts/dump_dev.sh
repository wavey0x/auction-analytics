#!/usr/bin/env bash
set -euo pipefail

# Dump a full logical backup of the dev DB, including schema + data
# Usage:
#   DEV_DATABASE_URL=postgres://... ./scripts/dump_dev.sh [out_dir] [--sql]
#
# - out_dir: directory to write dumps to (default: data/postgres)
# - --sql: also emit a plain SQL file alongside the custom archive

OUT_DIR="${1:-data/postgres}"
ALSO_SQL="${2:-}"  # pass --sql to enable

if [[ -z "${DEV_DATABASE_URL:-}" ]]; then
  echo "ERROR: DEV_DATABASE_URL is not set" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
ARCHIVE_PATH="${OUT_DIR%/}/auction_dev.dump"
SQL_PATH="${OUT_DIR%/}/full.sql"

echo "[dump_dev] Using DEV_DATABASE_URL=${DEV_DATABASE_URL%%\?*}"
echo "[dump_dev] Writing custom archive to: $ARCHIVE_PATH"

# Full logical dump in custom format (portable, includes schema+data)
pg_dump "$DEV_DATABASE_URL" \
  --format=custom \
  --file "$ARCHIVE_PATH" \
  --no-owner --no-privileges

echo "[dump_dev] Archive created. Quick contents peek (first 20 schema items):"
pg_restore --list "$ARCHIVE_PATH" | egrep -i "VIEW|INDEX|CONSTRAINT|TRIGGER|FUNCTION" | head -n 20 || true
echo "[dump_dev] Full manifest: pg_restore --list $ARCHIVE_PATH"

if [[ "$ALSO_SQL" == "--sql" ]]; then
  echo "[dump_dev] Also emitting plain SQL to: $SQL_PATH"
  pg_dump "$DEV_DATABASE_URL" \
    --format=plain \
    --file "$SQL_PATH" \
    --create --clean --if-exists \
    --no-owner --no-privileges
fi

echo "[dump_dev] Done."

