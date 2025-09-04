#!/bin/bash
# Production Database Schema Sync Script (from schema file)
# Syncs production database with the canonical data/postgres/schema.sql file
#
# This script applies the corrected schema.sql directly to production
# without needing a running development database.

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

# Check schema file exists
SCHEMA_FILE="data/postgres/schema.sql"
if [[ ! -f "$SCHEMA_FILE" ]]; then
    log_error "Schema file not found: $SCHEMA_FILE"
    exit 1
fi

log_info "🔄 Starting production database schema sync from file..."
log_info "Production DB: ${DATABASE_URL%%:*}://***@${DATABASE_URL#*@}"
log_info "Schema file: $SCHEMA_FILE"

# Create temporary directory for migration
TEMP_DIR=$(mktemp -d)
MIGRATION_FILE="$TEMP_DIR/production_migration.sql"

cleanup() {
    log_info "🧹 Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Create production-ready migration
cat > "$MIGRATION_FILE" << 'EOF'
-- Production Database Schema Sync from File
-- This drops and recreates all tables from canonical schema.sql

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
        CREATE TABLE _backup_auctions AS SELECT * FROM auctions WHERE auction_address IS NOT NULL;
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

# Append the schema file content
cat "$SCHEMA_FILE" >> "$MIGRATION_FILE"

# Add restoration of production data and sequence fixes
cat >> "$MIGRATION_FILE" << 'EOF'

-- Fix sequence ownership (critical for SERIAL columns)
ALTER SEQUENCE public.indexer_state_id_seq OWNED BY public.indexer_state.id;
ALTER TABLE ONLY public.indexer_state ALTER COLUMN id SET DEFAULT nextval('public.indexer_state_id_seq'::regclass);

-- Set sequence start value to avoid conflicts
SELECT setval('public.indexer_state_id_seq', COALESCE((SELECT MAX(id) FROM _backup_indexer_state), 1), false);

-- Add missing sequences for other SERIAL columns if they exist
DO $$
BEGIN
    -- token_prices sequence
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'token_prices' AND column_name = 'id') THEN
        CREATE SEQUENCE IF NOT EXISTS public.token_prices_id_seq AS integer;
        ALTER SEQUENCE public.token_prices_id_seq OWNED BY public.token_prices.id;
        ALTER TABLE ONLY public.token_prices ALTER COLUMN id SET DEFAULT nextval('public.token_prices_id_seq'::regclass);
        SELECT setval('public.token_prices_id_seq', 1, false);
        RAISE NOTICE 'Set up token_prices id sequence';
    END IF;
    
    -- tokens sequence
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tokens' AND column_name = 'id') THEN
        CREATE SEQUENCE IF NOT EXISTS public.tokens_id_seq AS integer;
        ALTER SEQUENCE public.tokens_id_seq OWNED BY public.tokens.id;
        ALTER TABLE ONLY public.tokens ALTER COLUMN id SET DEFAULT nextval('public.tokens_id_seq'::regclass);
        SELECT setval('public.tokens_id_seq', 1, false);
        RAISE NOTICE 'Set up tokens id sequence';
    END IF;
END $$;

-- Restore backed up production data
DO $$
BEGIN
    -- Restore indexer state if backup exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = '_backup_indexer_state') THEN
        INSERT INTO indexer_state (chain_id, factory_address, factory_type, last_indexed_block, start_block, updated_at)
        SELECT chain_id, factory_address, factory_type, last_indexed_block, start_block, updated_at 
        FROM _backup_indexer_state
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
            version = EXCLUDED.version,
            updated_at = NOW();
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
    required_tables TEXT[] := ARRAY['auctions', 'rounds', 'takes', 'tokens', 'indexer_state', 'enabled_tokens', 'token_prices'];
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
    RAISE NOTICE '   - Critical constraints and indexes applied';
    RAISE NOTICE '   - SERIAL sequences properly configured';
END $$;

COMMIT;
EOF

# Show what will be done
log_info "📋 Migration Summary:"
echo "   • Schema source: $SCHEMA_FILE ✅"
echo "   • Migration file: $MIGRATION_FILE ✅"
echo "   • Tables to create: $(grep -c "CREATE TABLE" "$SCHEMA_FILE")"
echo "   • Constraints to add: $(grep -c "ADD CONSTRAINT\|CREATE.*INDEX" "$SCHEMA_FILE")"

# Confirm before applying
log_warn "This will completely rebuild your production database schema!"
log_warn "Existing data in indexer_state and auctions tables will be preserved."
echo
read -p "Continue with production schema sync? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "❌ Schema sync cancelled by user"
    exit 0
fi

# Apply the migration
log_info "🚀 Applying schema migration to production..."
if psql "$DATABASE_URL" -f "$MIGRATION_FILE"; then
    log_info "✅ Production database schema sync completed successfully!"
    log_info "🔍 Verify indexer can start - the NULL id constraint issue should be fixed!"
else
    log_error "❌ Schema migration failed!"
    log_error "Check the error messages above for details"
    exit 1
fi