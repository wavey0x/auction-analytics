-- Migration 031: Add missing columns to auctions table for indexer compatibility
-- The indexer expects 'version' column instead of 'auction_version'

BEGIN;

-- Add version column if it doesn't exist (maps to old auction_version)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'auctions' AND column_name = 'version') THEN
        -- Check if we have the old column name to migrate from
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'auctions' AND column_name = 'auction_version') THEN
            -- Rename the column
            ALTER TABLE auctions RENAME COLUMN auction_version TO version;
            RAISE NOTICE '✅ Renamed auction_version to version';
        ELSE
            -- Add new column
            ALTER TABLE auctions ADD COLUMN version VARCHAR(20) DEFAULT '0.1.0';
            RAISE NOTICE '✅ Added version column with default 0.1.0';
        END IF;
    ELSE
        RAISE NOTICE 'ℹ️  version column already exists';
    END IF;
END $$;

-- Add any other missing columns the indexer might expect
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS update_interval INTEGER;
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS step_decay_rate DECIMAL(30,0);

-- Update column comments
COMMENT ON COLUMN auctions.version IS 'Contract version: 0.0.1 (legacy) or 0.1.0 (modern)';
COMMENT ON COLUMN auctions.update_interval IS 'Price update interval in seconds (mapped from update_interval)';
COMMENT ON COLUMN auctions.step_decay_rate IS 'Decay rate per step in RAY format (1e27)';

-- Copy data from update_interval to update_interval if needed
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'auctions' AND column_name = 'update_interval') THEN
        UPDATE auctions SET update_interval = update_interval WHERE update_interval IS NULL;
        RAISE NOTICE '✅ Copied update_interval to update_interval';
    END IF;
END $$;

-- Verification
DO $$
DECLARE
    missing_columns TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Check for critical columns the indexer needs
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'auctions' AND column_name = 'version') THEN
        missing_columns := array_append(missing_columns, 'version');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'auctions' AND column_name = 'update_interval') THEN
        missing_columns := array_append(missing_columns, 'update_interval');
    END IF;
    
    IF array_length(missing_columns, 1) > 0 THEN
        RAISE EXCEPTION 'Migration 031 failed: missing columns: %', array_to_string(missing_columns, ', ');
    ELSE
        RAISE NOTICE '✅ Migration 031 completed successfully:';
        RAISE NOTICE '  - Ensured version column exists for indexer compatibility';
        RAISE NOTICE '  - Added update_interval and step_decay_rate columns';
        RAISE NOTICE '  - Updated column documentation';
    END IF;
END $$;

COMMIT;