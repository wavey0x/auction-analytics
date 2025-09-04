# Fresh Installation Guide

This guide covers setting up the Auction Analytics system from scratch, including production database synchronization.

## Prerequisites

- **Node.js 18+** and **Python 3.9+**
- **Docker** and **Docker Compose** (for development database)
- **PostgreSQL access** (for production database)
- **Git** for cloning the repository

## Quick Start (Development)

```bash
# 1. Clone repository
git clone <repo-url>
cd auction-analytics

# 2. Setup environment
cp .env.example .env
# Edit .env with your configuration

# 3. Setup Python virtual environment
./setup_venv.sh

# 4. Start development stack
./dev.sh
```

## Production Installation

### Step 1: Environment Configuration

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Configure for production mode
vim .env  # Set the following:
```

**Required .env configuration:**
```bash
# Core configuration
APP_MODE=prod

# Production database
DATABASE_URL=postgresql://username:password@prod-host:5432/auction_prod

# Development database (needed for schema sync)
DEV_DATABASE_URL=postgresql://postgres:password@localhost:5433/auction_dev

# Network RPC URLs
ETHEREUM_RPC_URL=https://mainnet.infura.io/v3/YOUR_KEY
ETHEREUM_FACTORY_ADDRESS=0x_YOUR_DEPLOYED_FACTORY

# Additional networks (optional)
POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/YOUR_KEY
ARBITRUM_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/YOUR_KEY
```

### Step 2: Database Setup

#### 2a. Start Development Database (Required for Schema Sync)

The production sync process requires a running development database as the schema source:

```bash
# Start development PostgreSQL via Docker
docker-compose up -d postgres

# Verify development database is running
docker exec auction_postgres psql -U postgres -d auction_dev -c "SELECT COUNT(*) FROM information_schema.tables;"
```

#### 2b. Prepare Production Database

**On your production database server:**

```bash
# Create production database
sudo -u postgres createdb auction_prod

# Create application user
sudo -u postgres psql -c "CREATE USER auction WITH PASSWORD 'your_secure_password';"

# Grant permissions
sudo -u postgres psql auction_prod -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO auction;"
sudo -u postgres psql auction_prod -c "ALTER SCHEMA public OWNER TO auction;"
```

#### 2c. Sync Production Schema

**Critical step:** This synchronizes your production database with the latest development schema:

```bash
# Run the schema sync script
./scripts/sync_prod_with_dev_schema.sh

# You'll be prompted to confirm before applying changes
# Type 'y' when ready to proceed
```

**What this script does:**
- ✅ Extracts current dev database schema using Docker (avoids version conflicts)
- ✅ Creates production-safe migration script
- ✅ Drops and recreates all tables with latest structure
- ✅ Preserves existing production data if any (indexer_state, auctions)
- ✅ Sets proper ownership to auction user
- ✅ Verifies critical columns exist (round_start, round_end, etc.)

### Step 3: Service Deployment

#### 3a. Setup Python Environment

```bash
# Create unified virtual environment
./setup_venv.sh

# Verify installation
source venv/bin/activate
python3 -c "import asyncpg, web3; print('✅ Dependencies installed')"
```

#### 3b. Start Production Services

```bash
# Start API and indexer services (no UI)
./run.sh prod --no-ui

# Or start all services including UI
./run.sh prod
```

### Step 4: Verification

#### 4a. Verify Database Schema

```bash
# Test critical columns exist
psql $DATABASE_URL -c "SELECT round_end, round_start FROM public.rounds ORDER BY timestamp DESC LIMIT 1;"

# Check table structure
psql $DATABASE_URL -c "\dt"  # List all tables
psql $DATABASE_URL -c "\d rounds"  # Verify rounds table structure
```

#### 4b. Verify API Health

```bash
# Check API status
curl http://localhost:8000/health

# Check network connectivity
curl http://localhost:8000/networks

# View system stats
curl http://localhost:8000/system/stats
```

#### 4c. Monitor Indexing

```bash
# Check indexer progress
psql $DATABASE_URL -c "SELECT * FROM indexer_state ORDER BY updated_at DESC;"

# Monitor new data flowing in
watch -n 5 "psql $DATABASE_URL -c 'SELECT COUNT(*) FROM auctions; SELECT COUNT(*) FROM rounds; SELECT COUNT(*) FROM takes;'"
```

## Common Installation Issues

### Database Schema Issues

**Problem: "column round_start does not exist"**
```bash
# Solution: Re-run schema sync
./scripts/sync_prod_with_dev_schema.sh
```

**Problem: "Permission denied to drop schema"**
```bash
# Solution: Fix schema ownership
sudo -u postgres psql auction_prod -c "ALTER SCHEMA public OWNER TO auction;"
```

**Problem: "PostgreSQL version mismatch"**
- The sync script automatically handles this by using Docker pg_dump
- Ensure development database is running: `docker-compose up -d postgres`

### Network Connection Issues

**Problem: RPC connection failures**
```bash
# Check RPC URL is working
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $ETHEREUM_RPC_URL
```

**Problem: Factory address not found**
- Verify factory is deployed on the specified network
- Check factory address in block explorer
- Ensure indexer has proper permissions to query factory events

### Service Startup Issues

**Problem: "Port already in use"**
```bash
# Find and kill conflicting processes
lsof -i :8000
kill -9 <PID>
```

**Problem: "Virtual environment not found"**
```bash
# Recreate virtual environment
./setup_venv.sh
source venv/bin/activate
```

## Advanced Configuration

### Multiple Networks

Add additional networks to `.env`:

```bash
# Enable multiple networks
PROD_NETWORKS_ENABLED=ethereum,polygon,arbitrum,optimism,base

# Configure each network
POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/YOUR_KEY
POLYGON_FACTORY_ADDRESS=0x_YOUR_POLYGON_FACTORY
ARBITRUM_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/YOUR_KEY
ARBITRUM_FACTORY_ADDRESS=0x_YOUR_ARBITRUM_FACTORY
```

### Database Performance

For high-volume production:

```sql
-- Add additional indexes for performance
CREATE INDEX CONCURRENTLY idx_takes_recent ON takes (chain_id, timestamp DESC);
CREATE INDEX CONCURRENTLY idx_auctions_active ON auctions (chain_id) WHERE factory_address IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_rounds_active ON rounds (chain_id, round_end DESC) WHERE round_end > EXTRACT(EPOCH FROM NOW());
```

### Monitoring Setup

Add monitoring to your production deployment:

```bash
# Add to systemd service file
[Unit]
Description=Auction Analytics API
After=network.target postgresql.service

[Service]
Type=simple
User=auction
WorkingDirectory=/path/to/auction-analytics
Environment=DATABASE_URL=postgresql://auction:password@localhost:5432/auction_prod
ExecStart=/path/to/auction-analytics/venv/bin/python monitoring/api/app.py
Restart=always

[Install]
WantedBy=multi-user.target
```

## Deployment Checklist

### Pre-Deployment
- [ ] `.env` file configured with production values
- [ ] Development database running (for schema sync)
- [ ] Production database created with proper user permissions
- [ ] RPC URLs tested and working
- [ ] Factory addresses verified on each network

### Deployment Steps
- [ ] Schema sync completed successfully: `./scripts/sync_prod_with_dev_schema.sh`
- [ ] Python virtual environment created: `./setup_venv.sh`
- [ ] Production services started: `./run.sh prod`
- [ ] API health check passes: `curl http://localhost:8000/health`
- [ ] Network connectivity verified: `curl http://localhost:8000/networks`

### Post-Deployment
- [ ] Database tables populated: Check `auctions`, `rounds`, `takes` row counts
- [ ] Indexer progress advancing: Monitor `indexer_state` table
- [ ] No error logs in service output
- [ ] Performance monitoring configured
- [ ] Backup schedule configured

## Support

If you encounter issues during installation:

1. **Check logs**: Service logs contain detailed error information
2. **Verify configuration**: Ensure all `.env` values are correct
3. **Test components**: Use individual `curl` commands to test API endpoints
4. **Database access**: Verify you can connect and query the database directly
5. **Network connectivity**: Test RPC endpoints and factory addresses

For development setup, refer to the main `README.md`. For architecture details, see `architecture.md`.