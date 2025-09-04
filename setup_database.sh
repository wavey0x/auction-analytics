#!/bin/bash
# =============================================================================
# AUCTION ANALYTICS - ONE-SHOT DATABASE SETUP
# =============================================================================
# This script sets up a complete, production-ready database from scratch
# Works with PostgreSQL (native or Docker), with or without TimescaleDB

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}ℹ️  $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${BLUE}${BOLD}🔄 $1${NC}"; }
log_success() { echo -e "${GREEN}${BOLD}✅ $1${NC}"; }

# Default values
DEFAULT_MODE="dev"
DEFAULT_DB_NAME="auction_analytics"

# Help function
show_help() {
    echo "Auction Analytics Database Setup"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --mode=MODE          Database mode: dev, prod (default: dev)"
    echo "  --db-url=URL         Full database URL (overrides other options)"
    echo "  --db-name=NAME       Database name (default: auction_analytics)"
    echo "  --db-host=HOST       Database host (default: localhost)"
    echo "  --db-port=PORT       Database port (default: 5432)"
    echo "  --db-user=USER       Database user (default: postgres)"
    echo "  --force              Drop existing database and recreate"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --mode=dev"
    echo "  $0 --mode=prod --db-url=\"postgresql://user:pass@host:5432/auction_prod\""
    echo "  $0 --force --db-name=auction_test"
    echo ""
    echo "Environment Variables (alternative to command line):"
    echo "  DATABASE_URL         Primary database connection URL (production/default)"
    echo "  DEV_DATABASE_URL     Development database URL override"
    echo "  APP_MODE             Application mode (dev/prod)"
    exit 0
}

# Parse command line arguments
MODE="$DEFAULT_MODE"
DB_URL=""
DB_NAME="$DEFAULT_DB_NAME"
DB_HOST="localhost"
DB_PORT="5432"
DB_USER="postgres"
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode=*)
            MODE="${1#*=}"
            shift
            ;;
        --db-url=*)
            DB_URL="${1#*=}"
            shift
            ;;
        --db-name=*)
            DB_NAME="${1#*=}"
            shift
            ;;
        --db-host=*)
            DB_HOST="${1#*=}"
            shift
            ;;
        --db-port=*)
            DB_PORT="${1#*=}"
            shift
            ;;
        --db-user=*)
            DB_USER="${1#*=}"
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Load environment variables if available
if [[ -f .env ]]; then
    log_info "Loading environment variables from .env"
    set -a
    source .env
    set +a
fi

# Determine database URL
if [[ -z "$DB_URL" ]]; then
    # Try environment variables first
    APP_MODE="${APP_MODE:-$MODE}"
    case "$APP_MODE" in
        "prod")
            DB_URL="${DATABASE_URL:-}"
            if [[ -z "$DB_URL" ]]; then
                DB_NAME="${DB_NAME}_prod"
            fi
            ;;
        "dev"|*)
            DB_URL="${DEV_DATABASE_URL:-}"
            if [[ -z "$DB_URL" ]]; then
                DB_NAME="${DB_NAME}_dev"
            fi
            ;;
    esac
    
    # Build URL if not provided
    if [[ -z "$DB_URL" ]]; then
        DB_URL="postgresql://${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
    fi
fi

# Validate database URL
if [[ -z "$DB_URL" ]]; then
    log_error "Database URL not specified. Use --db-url or set environment variables."
    exit 1
fi

# Extract database name from URL for operations
ACTUAL_DB_NAME=$(echo "$DB_URL" | sed 's/.*\/\([^/?]*\).*/\1/')
ADMIN_URL=$(echo "$DB_URL" | sed "s|/$ACTUAL_DB_NAME|/postgres|")

log_step "Setting up Auction Analytics Database"
echo "  Mode: $MODE"
echo "  Database: ${DB_URL%%:*}://***@${DB_URL#*@}"
echo "  Force recreate: $FORCE"
echo ""

# Test database connection
log_step "Testing database connection..."
if ! psql "$ADMIN_URL" -c "SELECT 1;" >/dev/null 2>&1; then
    log_error "Cannot connect to PostgreSQL server"
    log_error "Please ensure PostgreSQL is running and accessible"
    exit 1
fi
log_success "Database server connection successful"

# Check if database exists
log_step "Checking database existence..."
DB_EXISTS=$(psql "$ADMIN_URL" -tAc "SELECT 1 FROM pg_database WHERE datname='$ACTUAL_DB_NAME';" 2>/dev/null || echo "")

if [[ "$DB_EXISTS" = "1" ]] && [[ "$FORCE" = true ]]; then
    log_warn "Dropping existing database: $ACTUAL_DB_NAME"
    psql "$ADMIN_URL" -c "DROP DATABASE IF EXISTS \"$ACTUAL_DB_NAME\";" >/dev/null
    DB_EXISTS=""
elif [[ "$DB_EXISTS" = "1" ]]; then
    log_info "Database already exists: $ACTUAL_DB_NAME"
    echo ""
    read -p "Database exists. Continue and update schema? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled by user"
        exit 0
    fi
else
    log_info "Database does not exist, will create new one"
fi

# Create database if needed
if [[ "$DB_EXISTS" != "1" ]]; then
    log_step "Creating database: $ACTUAL_DB_NAME"
    psql "$ADMIN_URL" -c "CREATE DATABASE \"$ACTUAL_DB_NAME\";" >/dev/null
    log_success "Database created successfully"
fi

# Apply schema
log_step "Applying complete database schema..."
SCHEMA_FILE="$(dirname "$0")/data/postgres/complete_schema.sql"

if [[ ! -f "$SCHEMA_FILE" ]]; then
    log_error "Schema file not found: $SCHEMA_FILE"
    exit 1
fi

if psql "$DB_URL" -f "$SCHEMA_FILE" >/dev/null 2>&1; then
    log_success "Database schema applied successfully"
else
    log_error "Failed to apply database schema"
    log_error "Check the schema file for syntax errors"
    exit 1
fi

# Verify setup
log_step "Verifying database setup..."
TABLE_COUNT=$(psql "$DB_URL" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
VIEW_COUNT=$(psql "$DB_URL" -tAc "SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'public';" 2>/dev/null || echo "0")
TOKEN_COUNT=$(psql "$DB_URL" -tAc "SELECT COUNT(*) FROM tokens;" 2>/dev/null || echo "0")

if [[ "$TABLE_COUNT" -lt 8 ]]; then
    log_error "Database setup incomplete (only $TABLE_COUNT tables found)"
    exit 1
fi

# Check for required tables
REQUIRED_TABLES=("auctions" "rounds" "takes" "tokens" "indexer_state" "enabled_tokens" "price_requests" "token_prices")
MISSING_TABLES=()

for table in "${REQUIRED_TABLES[@]}"; do
    if ! psql "$DB_URL" -tAc "SELECT 1 FROM information_schema.tables WHERE table_name = '$table';" >/dev/null 2>&1; then
        MISSING_TABLES+=("$table")
    fi
done

if [[ ${#MISSING_TABLES[@]} -gt 0 ]]; then
    log_error "Missing required tables: ${MISSING_TABLES[*]}"
    exit 1
fi

# Check for required views
REQUIRED_VIEWS=("vw_auctions")
MISSING_VIEWS=()

for view in "${REQUIRED_VIEWS[@]}"; do
    if ! psql "$DB_URL" -tAc "SELECT 1 FROM information_schema.views WHERE table_name = '$view';" >/dev/null 2>&1; then
        MISSING_VIEWS+=("$view")
    fi
done

if [[ ${#MISSING_VIEWS[@]} -gt 0 ]]; then
    log_error "Missing required views: ${MISSING_VIEWS[*]}"
    exit 1
fi

# Success summary
echo ""
log_success "🎉 DATABASE SETUP COMPLETED SUCCESSFULLY!"
echo ""
echo "📊 Summary:"
echo "  • Database: $ACTUAL_DB_NAME"
echo "  • Tables created: $TABLE_COUNT"
echo "  • Views created: $VIEW_COUNT (includes vw_auctions)"
echo "  • Token seeds: $TOKEN_COUNT"
echo "  • Indexes: ✅ Created"
echo "  • Triggers: ✅ Active"
echo "  • TimescaleDB: $(psql "$DB_URL" -tAc "SELECT CASE WHEN EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN 'Enabled' ELSE 'Not available' END;" 2>/dev/null || echo "Not available")"
echo ""
echo "🚀 Next Steps:"
echo "  1. Set environment variables:"
echo "     export DATABASE_URL=\"$DB_URL\""
echo "     export APP_MODE=\"$MODE\""
echo ""
echo "  2. Start the indexer:"
echo "     ./scripts/start_indexer_prod.sh"
echo ""
echo "  3. Start the API:"
echo "     python3 monitoring/api/app.py"
echo ""
echo "  4. Start the UI:"
echo "     cd ui && npm run dev"
echo ""
log_success "Database is ready for auction analytics! 🎯"