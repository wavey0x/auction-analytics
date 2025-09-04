#!/bin/bash
# Fix production database schema for indexer compatibility

set -euo pipefail

# Load environment variables
if [[ -f .env ]]; then
    source .env
fi

# Check if DATABASE_URL is set
if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "❌ DATABASE_URL not set in environment"
    exit 1
fi

echo "🚀 Applying schema fix to production database..."
echo "Database: ${DATABASE_URL%%:*}://***@${DATABASE_URL#*@}"

# Create and run the schema fix
psql "$DATABASE_URL" << 'EOF'
BEGIN;

-- Add missing timestamp column to tokens table
ALTER TABLE tokens ADD COLUMN IF NOT EXISTS timestamp BIGINT;
UPDATE tokens SET timestamp = EXTRACT(EPOCH FROM first_seen)::BIGINT WHERE timestamp IS NULL AND first_seen IS NOT NULL;
UPDATE tokens SET timestamp = EXTRACT(EPOCH FROM NOW())::BIGINT WHERE timestamp IS NULL;

-- Add missing columns to auctions table
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS version VARCHAR(20) DEFAULT '0.1.0';
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS decay_rate DECIMAL(10,4) DEFAULT 0.005;
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS auction_length INTEGER DEFAULT 3600;
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS starting_price DECIMAL(30,0);

-- Migrate data from old columns if they exist
DO $$
BEGIN
    -- Migrate from auction_version to version if needed
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'auctions' AND column_name = 'auction_version') 
       AND NOT EXISTS (SELECT 1 FROM auctions WHERE version IS NOT NULL LIMIT 1) THEN
        UPDATE auctions SET version = auction_version WHERE auction_version IS NOT NULL;
    END IF;
    
    -- Migrate from decay_rate_percent to decay_rate if needed
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'auctions' AND column_name = 'decay_rate_percent') THEN
        UPDATE auctions SET decay_rate = decay_rate_percent / 100.0 WHERE decay_rate_percent IS NOT NULL AND decay_rate IS NULL;
    END IF;
END $$;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_tokens_timestamp ON tokens (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_auctions_version ON auctions (version);

-- Verification
DO $$
BEGIN
    RAISE NOTICE '✅ Production schema fix completed successfully!';
    RAISE NOTICE '   - Added missing columns for indexer compatibility';  
    RAISE NOTICE '   - Indexer should now start without errors';
END $$;

COMMIT;
EOF

echo "✅ Schema fix applied successfully!"
echo ""
echo "Now restart the indexer:"
echo "   sudo systemctl restart auction-indexer"
echo "   sudo systemctl status auction-indexer"