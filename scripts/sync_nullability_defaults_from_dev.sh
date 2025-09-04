#!/usr/bin/env bash
set -euo pipefail

# Sync column nullability and defaults from DEV to PROD for a schema
#
# It compares information_schema for both DBs and generates ALTER TABLE
# statements so PROD matches DEV with respect to:
# - is_nullable (DROP/SET NOT NULL)
# - column_default (SET/DROP/replace default), skipping identity columns
#
# Usage:
#   DEV_DATABASE_URL=postgres://... \
#   DATABASE_URL=postgres://... \
#   ./scripts/sync_nullability_defaults_from_dev.sh [--schema=public] [--apply] [--output=path.sql]
#
# Notes:
# - Default schema: public
# - By default, prints the SQL plan; use --apply to execute
# - Identity columns are not modified

SCHEMA="public"
APPLY="no"
OUTPUT=""

for arg in "$@"; do
  case "$arg" in
    --schema=*) SCHEMA="${arg#*=}" ;;
    --apply) APPLY="yes" ;;
    --output=*) OUTPUT="${arg#*=}" ;;
    *) ;;
  esac
done

DEV_URL="${DEV_DATABASE_URL:-}"
PROD_URL="${DATABASE_URL:-${PROD_DATABASE_URL:-}}"
PSQL_BIN="${PSQL_BIN:-psql}"

if [[ -z "$DEV_URL" || -z "$PROD_URL" ]]; then
  echo "ERROR: set DEV_DATABASE_URL and DATABASE_URL/PROD_DATABASE_URL" >&2
  exit 1
fi

echo "[sync] Schema: $SCHEMA"
echo "[sync] DEV=${DEV_URL%%\?*}"
echo "[sync] PROD=${PROD_URL%%\?*}"

TMPDIR="${TMPDIR:-$(mktemp -d 2>/dev/null || mktemp -d -t tmp)}"
DEV_FILE="$TMPDIR/dev_cols.tsv"
PROD_FILE="$TMPDIR/prod_cols.tsv"
PLAN_FILE="$TMPDIR/plan.sql"

QUERY="
SELECT table_schema, table_name, column_name, is_nullable, COALESCE(column_default,''), is_identity
FROM information_schema.columns
WHERE table_schema = '$SCHEMA'
ORDER BY 1,2,3;"

"$PSQL_BIN" "$DEV_URL"  -AtF $'\t' -v ON_ERROR_STOP=1 -c "$QUERY" > "$DEV_FILE"
"$PSQL_BIN" "$PROD_URL" -AtF $'\t' -v ON_ERROR_STOP=1 -c "$QUERY" > "$PROD_FILE"

awk -F '\t' '
  NR==FNR { # DEV first pass
    key=$1"."$2"."$3
    dev_null[key]=$4
    dev_def[key]=$5
    dev_ident[key]=$6
    keys[key]=1
    next
  }
  { # PROD second pass
    key=$1"."$2"."$3
    prod_null[key]=$4
    prod_def[key]=$5
    prod_ident[key]=$6
    keys[key]=1
  }
  END {
    for (key in keys) {
      split(key, p, "."); schema=p[1]; tbl=p[2]; col=p[3];
      dn=dev_null[key]; pn=prod_null[key]
      dd=dev_def[key];  pd=prod_def[key]
      di=dev_ident[key]; pi=prod_ident[key]

      # Skip if column not present on either side
      if (dn=="" || pn=="") continue

      # Nullability: match prod to dev
      if (dn=="YES" && pn=="NO")
        printf "ALTER TABLE \"%s\".\"%s\" ALTER COLUMN \"%s\" DROP NOT NULL;\n", schema,tbl,col
      else if (dn=="NO" && pn=="YES")
        printf "ALTER TABLE \"%s\".\"%s\" ALTER COLUMN \"%s\" SET NOT NULL;\n", schema,tbl,col

      # Defaults: match prod to dev, skip if identity on either side
      if (di!="NO" || pi!="NO") {
        # identity columns handled elsewhere, skip default sync
        continue
      }
      if (dd=="" && pd!="")
        printf "ALTER TABLE \"%s\".\"%s\" ALTER COLUMN \"%s\" DROP DEFAULT;\n", schema,tbl,col
      else if (dd!="" && pd=="")
        printf "ALTER TABLE \"%s\".\"%s\" ALTER COLUMN \"%s\" SET DEFAULT %s;\n", schema,tbl,col, dd
      else if (dd!="" && pd!="" && dd!=pd)
        printf "ALTER TABLE \"%s\".\"%s\" ALTER COLUMN \"%s\" SET DEFAULT %s;\n", schema,tbl,col, dd
    }
  }
' "$DEV_FILE" "$PROD_FILE" > "$PLAN_FILE"

echo "[sync] Plan written: $PLAN_FILE"
if [[ -n "$OUTPUT" ]]; then
  cp "$PLAN_FILE" "$OUTPUT"
  echo "[sync] Plan copied to: $OUTPUT"
fi
if [[ -s "$PLAN_FILE" ]]; then
  echo "[sync] Preview (first 30 lines):"
  sed -n '1,30p' "$PLAN_FILE"
else
  echo "[sync] No differences detected for nullability/defaults in schema $SCHEMA"
fi

if [[ "$APPLY" == "yes" && -s "$PLAN_FILE" ]]; then
  echo "[sync] Applying plan..."
  "$PSQL_BIN" "$PROD_URL" -v ON_ERROR_STOP=1 -f "$PLAN_FILE"
  echo "[sync] Done."
fi
