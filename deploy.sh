#!/bin/bash
# =============================================================================
# AUCTION ANALYTICS - COMPLETE DEPLOYMENT SCRIPT
# =============================================================================
# One-shot deployment for the entire auction analytics system
# Handles database setup, environment configuration, and service startup

set -euo pipefail

# Colors and styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}ℹ️  $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${BLUE}${BOLD}🔄 $1${NC}"; }
log_success() { echo -e "${GREEN}${BOLD}✅ $1${NC}"; }
log_header() { echo -e "${PURPLE}${BOLD}🚀 $1${NC}"; }

# Default values
DEFAULT_MODE="prod"
DATABASE_URL=""
SKIP_DB=false
SKIP_SERVICES=false
SKIP_UI=false
DRY_RUN=false

# Help function
show_help() {
    echo -e "${BOLD}Auction Analytics - Complete Deployment Script${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --mode=MODE           Deployment mode: dev, prod (default: prod)"
    echo "  --database-url=URL    Database connection URL"
    echo "  --skip-database       Skip database setup"
    echo "  --skip-services       Skip backend services (API, indexer)"
    echo "  --skip-ui             Skip UI build and setup"
    echo "  --dry-run             Show what would be done without executing"
    echo "  --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --mode=prod --database-url=\"postgresql://user:pass@host/db\""
    echo "  $0 --mode=dev --skip-ui"
    echo "  $0 --dry-run"
    echo ""
    echo "Environment Variables:"
    echo "  DATABASE_URL          Primary database URL (production/default)"
    echo "  DEV_DATABASE_URL      Development database URL override"
    echo "  All other environment variables from .env file"
    exit 0
}

# Parse command line arguments
MODE="$DEFAULT_MODE"
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode=*)
            MODE="${1#*=}"
            shift
            ;;
        --database-url=*)
            DATABASE_URL="${1#*=}"
            shift
            ;;
        --skip-database)
            SKIP_DB=true
            shift
            ;;
        --skip-services)
            SKIP_SERVICES=true
            shift
            ;;
        --skip-ui)
            SKIP_UI=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

# Dry run helper
run_cmd() {
    if [[ "$DRY_RUN" = true ]]; then
        echo "  [DRY-RUN] $*"
    else
        "$@"
    fi
}

# Header
log_header "AUCTION ANALYTICS DEPLOYMENT"
echo "  Mode: $MODE"
echo "  Skip Database: $SKIP_DB"
echo "  Skip Services: $SKIP_SERVICES"
echo "  Skip UI: $SKIP_UI"
echo "  Dry Run: $DRY_RUN"
echo ""

# Validate mode
if [[ "$MODE" != "dev" && "$MODE" != "prod" ]]; then
    log_error "Invalid mode: $MODE (must be 'dev' or 'prod')"
    exit 1
fi

# Check if we're in the right directory
if [[ ! -f "package.json" && ! -f "pyproject.toml" && ! -f ".env.example" ]]; then
    log_error "Please run this script from the auction-analytics root directory"
    exit 1
fi

# ============================================================================
# STEP 1: ENVIRONMENT SETUP
# ============================================================================
log_step "Setting up environment configuration"

# Load environment variables
if [[ -f .env ]]; then
    log_info "Loading existing .env file"
    run_cmd set -a
    run_cmd source .env
    run_cmd set +a
elif [[ -f .env.example ]]; then
    log_warn ".env file not found, creating from example"
    run_cmd cp .env.example .env
    log_info "Please edit .env file with your configuration and run again"
    if [[ "$DRY_RUN" = false ]]; then
        exit 1
    fi
fi

# Set APP_MODE
export APP_MODE="$MODE"

# Determine database URL
if [[ -z "$DATABASE_URL" ]]; then
    case "$MODE" in
        "dev")
            DATABASE_URL="${DEV_DATABASE_URL:-}"
            ;;
        "prod"|*)
            # For production mode, DATABASE_URL should be set directly
            # No fallback needed since DATABASE_URL is the primary variable
            ;;
    esac
fi

if [[ -z "$DATABASE_URL" && "$SKIP_DB" = false ]]; then
    log_error "Database URL not specified for $MODE mode"
    if [[ "$MODE" = "dev" ]]; then
        log_error "Set DEV_DATABASE_URL in .env or use --database-url"
    else
        log_error "Set DATABASE_URL in .env or use --database-url"
    fi
    exit 1
fi

log_success "Environment configuration ready"

# ============================================================================
# STEP 2: DEPENDENCIES CHECK
# ============================================================================
log_step "Checking system dependencies"

# Check required commands
REQUIRED_COMMANDS=("python3" "psql" "node" "npm")
MISSING_COMMANDS=()

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_COMMANDS+=("$cmd")
    fi
done

if [[ ${#MISSING_COMMANDS[@]} -gt 0 ]]; then
    log_error "Missing required commands: ${MISSING_COMMANDS[*]}"
    log_error "Please install the missing dependencies and try again"
    exit 1
fi

log_success "All required dependencies available"

# ============================================================================
# STEP 3: DATABASE SETUP
# ============================================================================
if [[ "$SKIP_DB" = false ]]; then
    log_step "Setting up database"
    
    if [[ -f "./setup_database.sh" ]]; then
        if [[ "$DRY_RUN" = true ]]; then
            echo "  [DRY-RUN] ./setup_database.sh --mode=$MODE --db-url=\"$DATABASE_URL\""
        else
            if ! ./setup_database.sh --mode="$MODE" --db-url="$DATABASE_URL"; then
                log_error "Database setup failed"
                exit 1
            fi
        fi
        log_success "Database setup completed"
    else
        log_error "Database setup script not found"
        exit 1
    fi
else
    log_info "Skipping database setup (as requested)"
fi

# ============================================================================
# STEP 4: PYTHON ENVIRONMENT SETUP
# ============================================================================
if [[ "$SKIP_SERVICES" = false ]]; then
    log_step "Setting up Python environment"
    
    # Check for virtual environment script
    if [[ -f "./setup_venv.sh" ]]; then
        run_cmd ./setup_venv.sh
    else
        # Manual venv setup
        if [[ ! -d "venv" ]]; then
            log_info "Creating Python virtual environment"
            run_cmd python3 -m venv venv
        fi
        
        log_info "Installing Python dependencies"
        run_cmd source venv/bin/activate
        
        if [[ -f "requirements-working.txt" ]]; then
            run_cmd pip install -r requirements-working.txt
        elif [[ -f "requirements.txt" ]]; then
            run_cmd pip install -r requirements.txt
        else
            log_warn "No requirements file found, installing basic dependencies"
            run_cmd pip install fastapi uvicorn psycopg2-binary web3 pyyaml
        fi
    fi
    
    log_success "Python environment ready"
fi

# ============================================================================
# STEP 5: UI SETUP
# ============================================================================
if [[ "$SKIP_UI" = false ]]; then
    log_step "Setting up UI"
    
    if [[ -d "ui" ]]; then
        cd ui
        
        if [[ ! -d "node_modules" ]]; then
            log_info "Installing UI dependencies"
            run_cmd npm install
        else
            log_info "UI dependencies already installed"
        fi
        
        log_info "Building UI for production"
        run_cmd npm run build
        
        cd ..
        log_success "UI setup completed"
    else
        log_warn "UI directory not found, skipping UI setup"
    fi
fi

# ============================================================================
# STEP 6: SERVICE STARTUP
# ============================================================================
if [[ "$SKIP_SERVICES" = false ]]; then
    log_step "Starting services"
    
    # Export database URL for services
    export DATABASE_URL="$DATABASE_URL"
    
    # Start indexer
    if [[ -f "./scripts/start_indexer_prod.sh" ]]; then
        log_info "Starting indexer service"
        if [[ "$DRY_RUN" = true ]]; then
            echo "  [DRY-RUN] ./scripts/start_indexer_prod.sh (background)"
        else
            # Start in background for deployment
            nohup ./scripts/start_indexer_prod.sh > logs/indexer.log 2>&1 &
            INDEXER_PID=$!
            log_info "Indexer started (PID: $INDEXER_PID)"
        fi
    else
        log_warn "Indexer startup script not found"
    fi
    
    # Start API
    log_info "Starting API service"
    if [[ "$DRY_RUN" = true ]]; then
        echo "  [DRY-RUN] python3 monitoring/api/app.py (background)"
    else
        # Create logs directory
        mkdir -p logs
        
        # Start API in background
        nohup python3 monitoring/api/app.py > logs/api.log 2>&1 &
        API_PID=$!
        log_info "API started (PID: $API_PID)"
    fi
    
    # Start UI (if not skipped)
    if [[ "$SKIP_UI" = false && -d "ui" ]]; then
        log_info "Starting UI development server"
        if [[ "$DRY_RUN" = true ]]; then
            echo "  [DRY-RUN] cd ui && npm run dev (background)"
        else
            cd ui
            nohup npm run dev > ../logs/ui.log 2>&1 &
            UI_PID=$!
            cd ..
            log_info "UI started (PID: $UI_PID)"
        fi
    fi
    
    log_success "Services startup completed"
fi

# ============================================================================
# DEPLOYMENT COMPLETE
# ============================================================================
echo ""
log_header "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
echo ""

if [[ "$DRY_RUN" = false ]]; then
    echo "📊 Service Status:"
    if [[ "$SKIP_SERVICES" = false ]]; then
        echo "  • Database: ✅ Ready ($MODE mode)"
        echo "  • Indexer: ✅ Running (PID: ${INDEXER_PID:-N/A})"
        echo "  • API: ✅ Running (PID: ${API_PID:-N/A})"
        if [[ "$SKIP_UI" = false ]]; then
            echo "  • UI: ✅ Running (PID: ${UI_PID:-N/A})"
        fi
    fi
    
    echo ""
    echo "🌐 Access URLs:"
    echo "  • API Documentation: http://localhost:8000/docs"
    echo "  • UI Dashboard: http://localhost:3000"
    echo "  • API Health Check: http://localhost:8000/health"
    
    echo ""
    echo "📋 Useful Commands:"
    echo "  • View API logs: tail -f logs/api.log"
    echo "  • View indexer logs: tail -f logs/indexer.log"
    if [[ "$SKIP_UI" = false ]]; then
        echo "  • View UI logs: tail -f logs/ui.log"
    fi
    echo "  • Check database: psql \"$DATABASE_URL\" -c '\\dt'"
    
    echo ""
    echo "🔧 Management:"
    echo "  • Stop all: pkill -f 'python3 monitoring' && pkill -f 'npm run dev' && pkill -f 'indexer.py'"
    echo "  • Restart indexer: ./scripts/start_indexer_prod.sh"
    echo "  • Check system status: systemctl status auction-*"
else
    echo "  [DRY-RUN] No actual changes were made"
    echo "  Run without --dry-run to perform the actual deployment"
fi

echo ""
log_success "Auction Analytics is ready to go! 🎯"