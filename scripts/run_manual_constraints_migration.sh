#!/usr/bin/env bash
set -euo pipefail

# Runs the manual constraints migration and repairs PK identities.
# Usage:
#   DATABASE_URL=postgres://... ./scripts/run_manual_constraints_migration.sh
# Optional:
#   PSQL_BIN=psql ./scripts/run_manual_constraints_migration.sh

PSQL_BIN="${PSQL_BIN:-psql}"
TARGET_URL="${DATABASE_URL:-${PROD_DATABASE_URL:-}}"

if [[ -z "${TARGET_URL}" ]]; then
  echo "ERROR: set DATABASE_URL or PROD_DATABASE_URL" >&2
  exit 1
fi

echo "[manual-migration] Applying 039_unified_views.sql ..."
"$PSQL_BIN" "$TARGET_URL" -v ON_ERROR_STOP=1 -f data/postgres/migrations/039_unified_views.sql

echo "[manual-migration] Repairing primary key identities (safe, idempotent) ..."
./scripts/repair_primary_key_identities.sh --schema=public || {
  echo "[manual-migration] Warning: identity repair script failed; continuing." >&2
}

echo "[manual-migration] Done."
