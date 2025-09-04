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

# Allow overriding client tool paths
PG_DUMP_BIN="${PG_DUMP_BIN:-pg_dump}"
PG_RESTORE_BIN="${PG_RESTORE_BIN:-pg_restore}"
PSQL_BIN="${PSQL_BIN:-psql}"

if [[ -z "${DEV_DATABASE_URL:-}" ]]; then
  echo "ERROR: DEV_DATABASE_URL is not set" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
ARCHIVE_PATH="${OUT_DIR%/}/auction_dev.dump"
SQL_PATH="${OUT_DIR%/}/full.sql"

echo "[dump_dev] Using DEV_DATABASE_URL=${DEV_DATABASE_URL%%\?*}"
echo "[dump_dev] pg_dump: $PG_DUMP_BIN | pg_restore: $PG_RESTORE_BIN"
echo "[dump_dev] Writing custom archive to: $ARCHIVE_PATH"

# Optional quick version sanity check (non-fatal unless clearly incompatible)
SERVER_VER="$($PSQL_BIN -Atqc "show server_version" "$DEV_DATABASE_URL" 2>/dev/null || true)"
CLIENT_VER="$($PG_DUMP_BIN --version 2>/dev/null | awk '{print $NF}' || true)"
if [[ -n "$SERVER_VER" && -n "$CLIENT_VER" ]]; then
  srv_major="${SERVER_VER%%.*}"
  cli_major="${CLIENT_VER%%.*}"
  if [[ "$cli_major" -lt "$srv_major" ]]; then
    echo "ERROR: pg_dump major ($CLIENT_VER) is older than server ($SERVER_VER)." >&2
    echo "Hint: install pg_dump $srv_major.x (e.g., brew install libpq@$srv_major) and set PG_DUMP_BIN." >&2
    exit 2
  fi
fi

# Full logical dump in custom format (portable, includes schema+data)
$PG_DUMP_BIN "$DEV_DATABASE_URL" \
  --format=custom \
  --file "$ARCHIVE_PATH" \
  --no-owner --no-privileges

echo "[dump_dev] Archive created. Quick contents peek (first 20 schema items):"
"$PG_RESTORE_BIN" --list "$ARCHIVE_PATH" | egrep -i "VIEW|INDEX|CONSTRAINT|TRIGGER|FUNCTION" | head -n 20 || true
echo "[dump_dev] Full manifest: pg_restore --list $ARCHIVE_PATH"

if [[ "$ALSO_SQL" == "--sql" ]]; then
  echo "[dump_dev] Also emitting plain SQL to: $SQL_PATH"
  "$PG_DUMP_BIN" "$DEV_DATABASE_URL" \
    --format=plain \
    --file "$SQL_PATH" \
    --create --clean --if-exists \
    --no-owner --no-privileges
fi

echo "[dump_dev] Done."
