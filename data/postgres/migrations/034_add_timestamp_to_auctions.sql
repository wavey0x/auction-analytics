-- Migration 034: Add timestamp column to auctions table
-- The indexer expects a 'timestamp' column to store block timestamp when auction was deployed

BEGIN;

-- Add timestamp column if it doesn't exist 
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS timestamp BIGINT;

-- Populate existing records with discovered_at timestamp converted to Unix timestamp
UPDATE auctions 
SET timestamp = EXTRACT(EPOCH FROM discovered_at)::BIGINT 
WHERE timestamp IS NULL AND discovered_at IS NOT NULL;

-- For records without discovered_at, use a reasonable default (NOW)
UPDATE auctions 
SET timestamp = EXTRACT(EPOCH FROM NOW())::BIGINT 
WHERE timestamp IS NULL;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_auctions_timestamp ON auctions (timestamp DESC);

-- Add comment to document the column
COMMENT ON COLUMN auctions.timestamp IS 'Unix timestamp when auction was deployed (from block timestamp)';

-- Verification
DO $$
DECLARE
    timestamp_exists BOOLEAN;
    null_count INTEGER;
BEGIN
    -- Check if timestamp column exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'auctions' AND column_name = 'timestamp'
    ) INTO timestamp_exists;
    
    IF NOT timestamp_exists THEN
        RAISE EXCEPTION 'Migration 034 failed: timestamp column was not created';
    END IF;
    
    -- Check for any null values
    SELECT COUNT(*) INTO null_count FROM auctions WHERE timestamp IS NULL;
    
    IF null_count > 0 THEN
        RAISE WARNING 'Migration 034 warning: % auction records still have null timestamp', null_count;
    END IF;
    
    RAISE NOTICE '✅ Migration 034 completed successfully:';
    RAISE NOTICE '  - Added timestamp column to auctions table';
    RAISE NOTICE '  - Populated existing records from discovered_at';
    RAISE NOTICE '  - Created performance index';
    RAISE NOTICE '  - Indexer timestamp compatibility restored';
END $$;

COMMIT;