#!/usr/bin/env bash
set -euo pipefail

# Simple migration runner for Postgres using psql
# - Uses $DATABASE_URL (preferred) or $DEV_DATABASE_URL fallback
# - Applies data/postgres/schema.sql if database is empty
# - Applies all SQL files in data/postgres/migrations in semantic order

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA_FILE="$ROOT_DIR/data/postgres/schema.sql"
MIGRATIONS_DIR="$ROOT_DIR/data/postgres/migrations"

DB_URL="${DATABASE_URL:-}"
if [[ -z "$DB_URL" ]] ; then
  DB_URL="${DEV_DATABASE_URL:-${DATABASE_URL:-}}"
fi

if [[ -z "$DB_URL" ]] ; then
  echo "DATABASE_URL not set (or DEV_DATABASE_URL fallback)." >&2
  exit 1
fi

echo "Using DATABASE_URL: ${DB_URL%%:*}://***@${DB_URL#*@}"

psql_run() {
  PGPASSWORD="${PGPASSWORD:-}" psql "$DB_URL" -v ON_ERROR_STOP=1 -q -c "$1"
}

# Create database if needed (only for URL forms without DB created); best-effort
create_db_if_missing() {
  # Attempt a simple query; if it fails with database does not exist, create it
  if ! psql "$DB_URL" -q -c "SELECT 1;" >/dev/null 2>&1; then
    echo "Database not reachable. Attempting to create database (best-effort)."
    proto_host="${DB_URL%/*}"
    db_name="${DB_URL##*/}"
    admin_url="$proto_host/postgres"
    if psql "$admin_url" -q -c "SELECT 1;" >/dev/null 2>&1; then
      psql "$admin_url" -v ON_ERROR_STOP=1 -q -c "CREATE DATABASE \"$db_name\";" || true
    fi
  fi
}

create_db_if_missing

# Determine if schema is empty by checking a known table
echo "Checking for existing schema..."
if ! psql_run "SELECT 1 FROM information_schema.tables WHERE table_name='auctions'" >/dev/null 2>&1; then
  echo "Applying base schema: $SCHEMA_FILE"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SCHEMA_FILE"
else
  echo "Base tables detected; skipping schema.sql"
fi

echo "Applying migrations in $MIGRATIONS_DIR"
shopt -s nullglob
mapfile -t files < <(ls -1 "$MIGRATIONS_DIR"/*.sql | sort -V)
for f in "${files[@]}"; do
  echo "-> $f"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$f"
done
echo "Migrations applied successfully."

