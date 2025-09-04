-- Migration 032: Fix remaining schema issues for indexer compatibility
-- Adds missing columns that the indexer expects

BEGIN;

-- ============================================================================
-- FIX TOKENS TABLE SCHEMA
-- ============================================================================
-- Add missing timestamp column to tokens table
ALTER TABLE tokens ADD COLUMN IF NOT EXISTS timestamp BIGINT;

-- Update timestamp for existing records (use created timestamp)
UPDATE tokens 
SET timestamp = EXTRACT(EPOCH FROM first_seen)::BIGINT 
WHERE timestamp IS NULL AND first_seen IS NOT NULL;

-- Set default for new records
ALTER TABLE tokens ALTER COLUMN timestamp SET DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT;

-- Add comment
COMMENT ON COLUMN tokens.timestamp IS 'Unix timestamp when token was first discovered';

-- ============================================================================
-- FIX AUCTIONS TABLE SCHEMA  
-- ============================================================================
-- Add missing decay_rate column (human-readable version of step_decay_rate)
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS decay_rate DECIMAL(10,4);

-- Migrate from decay_rate_percent if it exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'auctions' AND column_name = 'decay_rate_percent') THEN
        UPDATE auctions SET decay_rate = decay_rate_percent / 100.0 WHERE decay_rate IS NULL;
        RAISE NOTICE '✅ Migrated decay_rate_percent to decay_rate (converted percentages to decimals)';
    END IF;
END $$;

-- Set reasonable default for new records (0.5% decay = 0.005)
UPDATE auctions SET decay_rate = 0.005 WHERE decay_rate IS NULL;

-- Add other missing columns the indexer might expect
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS auction_length INTEGER DEFAULT 3600; -- 1 hour default
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS starting_price DECIMAL(30,0);

-- Migrate from fixed_starting_price if it exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'auctions' AND column_name = 'fixed_starting_price') THEN
        UPDATE auctions SET starting_price = fixed_starting_price WHERE starting_price IS NULL AND fixed_starting_price IS NOT NULL;
        RAISE NOTICE '✅ Migrated fixed_starting_price to starting_price';
    END IF;
END $$;

-- Add comments for clarity
COMMENT ON COLUMN auctions.decay_rate IS 'Human-readable decay rate per step (e.g., 0.005 = 0.5% decay)';
COMMENT ON COLUMN auctions.auction_length IS 'Duration of each auction round in seconds';
COMMENT ON COLUMN auctions.starting_price IS 'Fixed starting price in wei, or NULL for dynamic pricing';

-- ============================================================================
-- ADD MISSING INDEXES FOR PERFORMANCE
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_tokens_timestamp ON tokens (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_auctions_version ON auctions (version);
CREATE INDEX IF NOT EXISTS idx_auctions_decay_rate ON auctions (decay_rate);

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
DECLARE
    tokens_timestamp_exists BOOLEAN;
    auctions_decay_rate_exists BOOLEAN;
    auctions_auction_length_exists BOOLEAN;
    missing_columns TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Check tokens table
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tokens' AND column_name = 'timestamp') INTO tokens_timestamp_exists;
    IF NOT tokens_timestamp_exists THEN
        missing_columns := array_append(missing_columns, 'tokens.timestamp');
    END IF;
    
    -- Check auctions table
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'auctions' AND column_name = 'decay_rate') INTO auctions_decay_rate_exists;
    IF NOT auctions_decay_rate_exists THEN
        missing_columns := array_append(missing_columns, 'auctions.decay_rate');
    END IF;
    
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'auctions' AND column_name = 'auction_length') INTO auctions_auction_length_exists;
    IF NOT auctions_auction_length_exists THEN
        missing_columns := array_append(missing_columns, 'auctions.auction_length');
    END IF;
    
    -- Report results
    IF array_length(missing_columns, 1) > 0 THEN
        RAISE EXCEPTION 'Migration 032 failed: missing columns: %', array_to_string(missing_columns, ', ');
    ELSE
        RAISE NOTICE '✅ Migration 032 completed successfully:';
        RAISE NOTICE '  - Added timestamp column to tokens table';
        RAISE NOTICE '  - Added decay_rate, auction_length, starting_price to auctions table';
        RAISE NOTICE '  - Migrated data from old column names where possible';
        RAISE NOTICE '  - Created performance indexes';
        RAISE NOTICE '  - Indexer schema compatibility restored';
    END IF;
END $$;

COMMIT;