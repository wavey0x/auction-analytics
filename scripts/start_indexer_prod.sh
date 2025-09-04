#!/bin/bash
# Production-safe indexer startup script
# Explicitly excludes local/Anvil networks and validates production environment

set -euo pipefail

# Set production environment
export APP_MODE=prod

# Source environment variables (adjust path as needed)
if [[ -f /opt/auction-app/.env ]]; then
    set -a  # automatically export all variables
    source /opt/auction-app/.env
    set +a
elif [[ -f .env ]]; then
    set -a
    source .env
    set +a
fi

# Production safety checks
if [[ "${APP_MODE:-}" != "prod" ]]; then
    echo "❌ APP_MODE must be set to 'prod' for production indexer"
    exit 1
fi

# Validate required production environment variables
required_vars=(
    "DATABASE_URL"
    "PROD_DATABASE_URL" 
    "PROD_NETWORKS_ENABLED"
)

missing_vars=()
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo "❌ Missing required environment variables: ${missing_vars[*]}"
    exit 1
fi

# Ensure NETWORKS_ENABLED excludes 'local'
export NETWORKS_ENABLED="${PROD_NETWORKS_ENABLED}"

if [[ "${NETWORKS_ENABLED}" == *"local"* ]]; then
    echo "❌ FATAL: NETWORKS_ENABLED contains 'local' network in production mode"
    echo "    Current value: ${NETWORKS_ENABLED}"
    echo "    This would attempt to connect to Anvil testnet (chain 31337)"
    echo "    Please update PROD_NETWORKS_ENABLED to exclude 'local'"
    exit 1
fi

# Set database URL for production
export DATABASE_URL="${PROD_DATABASE_URL}"

echo "🚀 Starting production indexer..."
echo "   Networks: ${NETWORKS_ENABLED}"
echo "   Database: ${DATABASE_URL%%:*}://***@${DATABASE_URL#*@}"
echo "   Mode: ${APP_MODE}"

# Change to indexer directory
cd "$(dirname "$0")/../indexer"

# Start indexer with explicit network filtering (double safety)
exec python3 indexer.py --network "${NETWORKS_ENABLED//,/ }" --config config.yaml