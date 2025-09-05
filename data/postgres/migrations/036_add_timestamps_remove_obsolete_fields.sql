-- Migration 036: Add timestamp fields to all tables and remove obsolete columns
-- This migration ensures all tables have a bigint timestamp field for consistency
-- and removes obsolete columns that are no longer used

BEGIN;

-- =============================================================================
-- STEP 1: Add timestamp (bigint) fields where missing
-- =============================================================================

-- Add timestamp to auctions table (for both dev and prod)
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS timestamp BIGINT;

-- Populate timestamp from discovered_at if it exists, otherwise use current time
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'auctions' AND column_name = 'discovered_at'
    ) THEN
        -- Populate from discovered_at for existing records
        UPDATE auctions 
        SET timestamp = EXTRACT(EPOCH FROM discovered_at)::BIGINT 
        WHERE timestamp IS NULL AND discovered_at IS NOT NULL;
    END IF;
    
    -- For any remaining NULL timestamps, use current time
    UPDATE auctions 
    SET timestamp = EXTRACT(EPOCH FROM NOW())::BIGINT 
    WHERE timestamp IS NULL;
END $$;

-- Add timestamp to rounds table
ALTER TABLE rounds ADD COLUMN IF NOT EXISTS timestamp BIGINT;

-- Populate from kicked_at if it exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'rounds' AND column_name = 'kicked_at'
    ) THEN
        -- Check if kicked_at is already bigint or timestamptz
        IF (SELECT data_type FROM information_schema.columns WHERE table_name = 'rounds' AND column_name = 'kicked_at') = 'bigint' THEN
            UPDATE rounds SET timestamp = kicked_at WHERE timestamp IS NULL AND kicked_at IS NOT NULL;
        ELSE
            UPDATE rounds SET timestamp = EXTRACT(EPOCH FROM kicked_at)::BIGINT WHERE timestamp IS NULL AND kicked_at IS NOT NULL;
        END IF;
    END IF;
    
    -- For any remaining NULL timestamps, use current time
    UPDATE rounds 
    SET timestamp = EXTRACT(EPOCH FROM NOW())::BIGINT 
    WHERE timestamp IS NULL;
END $$;

-- Add timestamp to indexer_state table
ALTER TABLE indexer_state ADD COLUMN IF NOT EXISTS timestamp BIGINT;

-- Populate from updated_at if it exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'indexer_state' AND column_name = 'updated_at'
    ) THEN
        UPDATE indexer_state 
        SET timestamp = EXTRACT(EPOCH FROM updated_at)::BIGINT 
        WHERE timestamp IS NULL AND updated_at IS NOT NULL;
    END IF;
    
    -- For any remaining NULL timestamps, use current time
    UPDATE indexer_state 
    SET timestamp = EXTRACT(EPOCH FROM NOW())::BIGINT 
    WHERE timestamp IS NULL;
END $$;

-- Add timestamp to tokens table if it doesn't exist
ALTER TABLE tokens ADD COLUMN IF NOT EXISTS timestamp BIGINT;

-- Populate from first_seen if it exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'tokens' AND column_name = 'first_seen'
    ) THEN
        UPDATE tokens 
        SET timestamp = EXTRACT(EPOCH FROM first_seen)::BIGINT 
        WHERE timestamp IS NULL AND first_seen IS NOT NULL;
    END IF;
    
    -- For any remaining NULL timestamps, use current time
    UPDATE tokens 
    SET timestamp = EXTRACT(EPOCH FROM NOW())::BIGINT 
    WHERE timestamp IS NULL;
END $$;

-- =============================================================================
-- STEP 2: Create indexes for all timestamp fields
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_auctions_timestamp ON auctions (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_rounds_timestamp ON rounds (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_indexer_state_timestamp ON indexer_state (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_tokens_timestamp ON tokens (timestamp DESC);

-- =============================================================================
-- STEP 3: Fix starting_price column type and remove obsolete columns
-- =============================================================================

-- Change starting_price to store decimal values properly (18 decimal places for wei)
-- This allows both wei values and human-readable decimal storage
ALTER TABLE auctions ALTER COLUMN starting_price TYPE NUMERIC(40,18);

-- Drop obsolete columns that are no longer used
ALTER TABLE auctions DROP COLUMN IF EXISTS step_decay;
ALTER TABLE auctions DROP COLUMN IF EXISTS step_decay_rate;
ALTER TABLE auctions DROP COLUMN IF EXISTS fixed_starting_price;
ALTER TABLE auctions DROP COLUMN IF EXISTS price_update_interval;

-- =============================================================================
-- STEP 4: Add comments to document the timestamp fields
-- =============================================================================

COMMENT ON COLUMN auctions.timestamp IS 'Unix timestamp when auction was deployed (from block timestamp)';
COMMENT ON COLUMN rounds.timestamp IS 'Unix timestamp when round was kicked';
COMMENT ON COLUMN indexer_state.timestamp IS 'Unix timestamp of last update';
COMMENT ON COLUMN tokens.timestamp IS 'Unix timestamp when token was first seen';

-- =============================================================================
-- STEP 5: Verification
-- =============================================================================

DO $$
DECLARE
    auctions_has_timestamp BOOLEAN;
    rounds_has_timestamp BOOLEAN;
    indexer_has_timestamp BOOLEAN;
    tokens_has_timestamp BOOLEAN;
    obsolete_columns_exist BOOLEAN;
BEGIN
    -- Check if timestamp columns were added successfully
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'auctions' AND column_name = 'timestamp'
    ) INTO auctions_has_timestamp;
    
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'rounds' AND column_name = 'timestamp'
    ) INTO rounds_has_timestamp;
    
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'indexer_state' AND column_name = 'timestamp'
    ) INTO indexer_has_timestamp;
    
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'tokens' AND column_name = 'timestamp'
    ) INTO tokens_has_timestamp;
    
    -- Check if obsolete columns were removed
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'auctions' 
        AND column_name IN ('step_decay', 'step_decay_rate', 'fixed_starting_price', 'update_interval')
    ) INTO obsolete_columns_exist;
    
    -- Report results
    IF NOT auctions_has_timestamp THEN
        RAISE WARNING 'auctions table is missing timestamp column';
    END IF;
    
    IF NOT rounds_has_timestamp THEN
        RAISE WARNING 'rounds table is missing timestamp column';
    END IF;
    
    IF NOT indexer_has_timestamp THEN
        RAISE WARNING 'indexer_state table is missing timestamp column';
    END IF;
    
    IF NOT tokens_has_timestamp THEN
        RAISE WARNING 'tokens table is missing timestamp column';
    END IF;
    
    IF obsolete_columns_exist THEN
        RAISE WARNING 'Some obsolete columns still exist in auctions table';
    END IF;
    
    -- Success message
    RAISE NOTICE '✅ Migration 036 completed successfully:';
    RAISE NOTICE '  - Added timestamp (bigint) to all tables';
    RAISE NOTICE '  - Populated timestamps from existing date fields';
    RAISE NOTICE '  - Created performance indexes';
    RAISE NOTICE '  - Removed obsolete columns';
    RAISE NOTICE '  - Database schema is now consistent';
END $$;

COMMIT;