#!/usr/bin/env bash
set -euo pipefail

# Audits the database for common post-restore issues:
# - Integer PK columns missing identity/default
# - NOT NULL columns with no default (may be fine; just surfaces)
#
# Usage:
#   DATABASE_URL=postgres://... ./scripts/post_restore_audit.sh
#   # or
#   PROD_DATABASE_URL=postgres://... ./scripts/post_restore_audit.sh

PSQL_BIN="${PSQL_BIN:-psql}"
TARGET_URL="${DATABASE_URL:-${PROD_DATABASE_URL:-}}"

if [[ -z "${TARGET_URL}" ]]; then
  echo "ERROR: set DATABASE_URL or PROD_DATABASE_URL" >&2
  exit 1
fi

echo "[audit] Using URL=${TARGET_URL%%\?*}"

echo "[audit] Integer PKs missing identity/default:"
"$PSQL_BIN" "$TARGET_URL" -F $'\t' -A -v ON_ERROR_STOP=1 -c "
WITH pk_cols AS (
  SELECT c.table_schema, c.table_name, c.column_name, c.udt_name, c.column_default, c.is_identity
  FROM information_schema.columns c
  JOIN information_schema.table_constraints tc
    ON tc.table_schema=c.table_schema AND tc.table_name=c.table_name AND tc.constraint_type='PRIMARY KEY'
  JOIN information_schema.key_column_usage k
    ON k.table_schema=tc.table_schema AND k.table_name=tc.table_name AND k.constraint_name=tc.constraint_name AND k.column_name=c.column_name
)
SELECT table_schema, table_name, column_name, udt_name, COALESCE(column_default, ''), is_identity
FROM pk_cols
WHERE udt_name IN ('int2','int4','int8')
  AND (column_default IS NULL OR column_default = '')
  AND is_identity = 'NO'
ORDER BY table_schema, table_name;"

echo
echo "[audit] NOT NULL columns with no default (review as needed):"
"$PSQL_BIN" "$TARGET_URL" -F $'\t' -A -v ON_ERROR_STOP=1 -c "
SELECT table_schema, table_name, column_name, udt_name, is_nullable, COALESCE(column_default,'') AS column_default
FROM information_schema.columns
WHERE is_nullable = 'NO'
  AND (column_default IS NULL OR column_default = '')
  AND table_schema NOT IN ('pg_catalog','information_schema')
ORDER BY table_schema, table_name;"

echo "[audit] Done."

