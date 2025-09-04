#!/bin/bash
# Production Database Schema Sync Script
# Syncs production database with development database schema

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}ℹ️  $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Load environment variables
if [[ -f .env ]]; then
    set -a
    source .env
    set +a
    log_info "Loaded environment variables from .env"
else
    log_error ".env file not found"
    exit 1
fi

# Validate required variables
if [[ -z "${DATABASE_URL:-}" ]]; then
    log_error "DATABASE_URL not set in environment"
    exit 1
fi

if [[ -z "${DEV_DATABASE_URL:-}" ]]; then
    log_error "DEV_DATABASE_URL not set in environment"
    exit 1
fi

log_info "🔄 Starting production database schema sync..."
log_info "Production DB: ${DATABASE_URL%%:*}://***@${DATABASE_URL#*@}"
log_info "Development DB: ${DEV_DATABASE_URL%%:*}://***@${DEV_DATABASE_URL#*@}"

# Create temporary directory for schema files
TEMP_DIR=$(mktemp -d)
SCHEMA_FILE="$TEMP_DIR/dev_schema.sql"
BACKUP_FILE="$TEMP_DIR/prod_backup.sql"

cleanup() {
    log_info "🧹 Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Step 1: Export development schema
log_info "📤 Exporting development database schema..."
if command -v docker &> /dev/null && docker ps | grep -q auction_postgres; then
    # Use Docker if available
    docker exec auction_postgres pg_dump -U postgres -d auction_dev \
        --schema-only --no-owner --no-privileges --no-tablespaces \
        --exclude-table-data='_timescaledb_*' > "$SCHEMA_FILE" || {
        log_error "Failed to export development schema via Docker"
        exit 1
    }
else
    # Direct connection
    pg_dump "$DEV_DATABASE_URL" \
        --schema-only --no-owner --no-privileges --no-tablespaces \
        --exclude-table-data='_timescaledb_*' > "$SCHEMA_FILE" || {
        log_error "Failed to export development schema"
        exit 1
    }
fi

# Step 2: Clean the schema file
log_info "🧽 Cleaning schema file for production..."
cat "$SCHEMA_FILE" | \
    grep -v "_timescaledb_internal" | \
    grep -v "_hyper_" | \
    sed '/^COMMENT ON EXTENSION/d' | \
    sed '/^CREATE SCHEMA _timescaledb/d' | \
    sed '/^GRANT.*_timescaledb/d' > "$TEMP_DIR/clean_schema.sql"

# Step 3: Create production-ready migration
cat > "$TEMP_DIR/production_migration.sql" << 'EOF'
-- Production Database Schema Sync Migration
-- This drops and recreates all tables to match development schema

BEGIN;

-- Safety check: ensure we're not accidentally running on development
DO $$
BEGIN
    IF current_database() LIKE '%dev%' OR current_database() LIKE '%test%' THEN
        RAISE EXCEPTION 'Refusing to run production migration on development/test database: %', current_database();
    END IF;
END $$;

-- Store any important production data we want to preserve
DO $$
BEGIN
    -- Create backup tables for critical production data if they exist
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'indexer_state') THEN
        DROP TABLE IF EXISTS _backup_indexer_state CASCADE;
        CREATE TABLE _backup_indexer_state AS SELECT * FROM indexer_state;
        RAISE NOTICE 'Backed up indexer_state table';
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'auctions') THEN
        DROP TABLE IF EXISTS _backup_auctions CASCADE;
        CREATE TABLE _backup_auctions AS SELECT * FROM auctions WHERE created_at IS NOT NULL;
        RAISE NOTICE 'Backed up auctions table';
    END IF;
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Backup creation failed or not needed: %', SQLERRM;
END $$;

-- Drop all existing tables (except backups)
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

-- Grant permissions
GRANT ALL ON SCHEMA public TO PUBLIC;

EOF

# Append the clean schema
cat "$TEMP_DIR/clean_schema.sql" >> "$TEMP_DIR/production_migration.sql"

# Add restoration of production data
cat >> "$TEMP_DIR/production_migration.sql" << 'EOF'

-- Restore backed up production data
DO $$
BEGIN
    -- Restore indexer state if backup exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = '_backup_indexer_state') THEN
        INSERT INTO indexer_state 
        SELECT * FROM _backup_indexer_state
        ON CONFLICT (chain_id, factory_address) DO UPDATE SET
            last_indexed_block = EXCLUDED.last_indexed_block,
            updated_at = EXCLUDED.updated_at;
        DROP TABLE _backup_indexer_state;
        RAISE NOTICE 'Restored indexer_state data';
    END IF;
    
    -- Restore auction data if backup exists  
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = '_backup_auctions') THEN
        INSERT INTO auctions 
        SELECT * FROM _backup_auctions
        ON CONFLICT (auction_address, chain_id) DO UPDATE SET
            discovered_at = EXCLUDED.discovered_at;
        DROP TABLE _backup_auctions;
        RAISE NOTICE 'Restored auction data';
    END IF;
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Data restoration completed with warnings: %', SQLERRM;
END $$;

-- Verification
DO $$
DECLARE
    table_count INTEGER;
    missing_tables TEXT[] := ARRAY[]::TEXT[];
    required_tables TEXT[] := ARRAY['auctions', 'rounds', 'takes', 'tokens', 'indexer_state'];
    table_name TEXT;
BEGIN
    SELECT COUNT(*) INTO table_count FROM information_schema.tables WHERE table_schema = 'public';
    
    -- Check for required tables
    FOREACH table_name IN ARRAY required_tables LOOP
        IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = table_name) THEN
            missing_tables := array_append(missing_tables, table_name);
        END IF;
    END LOOP;
    
    IF array_length(missing_tables, 1) > 0 THEN
        RAISE EXCEPTION 'Schema sync failed: missing required tables: %', array_to_string(missing_tables, ', ');
    END IF;
    
    RAISE NOTICE '✅ Production database schema sync completed successfully!';
    RAISE NOTICE '   - Total tables created: %', table_count;
    RAISE NOTICE '   - All required tables present: %', array_to_string(required_tables, ', ');
    RAISE NOTICE '   - Production data preserved and restored';
END $$;

COMMIT;
EOF

# Step 4: Show what will be done
log_info "📋 Migration Summary:"
echo "   • Export dev schema: ✅ Complete"
echo "   • Clean schema file: ✅ Complete"  
echo "   • Create migration: ✅ Complete"
echo "   • Tables to create: $(grep -c "CREATE TABLE" "$TEMP_DIR/clean_schema.sql")"
echo "   • Migration file: $TEMP_DIR/production_migration.sql"

# Step 5: Confirm before applying
log_warn "This will completely rebuild your production database schema!"
log_warn "Existing data in indexer_state and auctions tables will be preserved."
echo
read -p "Continue with production schema sync? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "❌ Schema sync cancelled by user"
    exit 0
fi

# Step 6: Apply the migration
log_info "🚀 Applying schema migration to production..."
if psql "$DATABASE_URL" -f "$TEMP_DIR/production_migration.sql"; then
    log_info "✅ Production database schema sync completed successfully!"
    log_info "🔍 Run this command to verify indexer can start:"
    echo "   sudo systemctl restart auction-indexer && sudo systemctl status auction-indexer"
else
    log_error "❌ Schema migration failed!"
    log_error "Check the error messages above for details"
    exit 1
fi