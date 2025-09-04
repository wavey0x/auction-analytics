-- Migration 029: Add missing columns to indexer_state table
-- The custom indexer expects start_block and factory_address columns

BEGIN;

-- Add missing columns to indexer_state table
ALTER TABLE indexer_state ADD COLUMN IF NOT EXISTS start_block INTEGER DEFAULT 0;
ALTER TABLE indexer_state ADD COLUMN IF NOT EXISTS factory_address VARCHAR(100);

-- Create index for factory_address queries
CREATE INDEX IF NOT EXISTS idx_indexer_state_factory ON indexer_state (factory_address);

-- Add comments to document the columns
COMMENT ON COLUMN indexer_state.start_block IS 'Starting block number for this indexer instance';
COMMENT ON COLUMN indexer_state.factory_address IS 'Factory address being tracked by this indexer instance';
COMMENT ON TABLE indexer_state IS 'Tracks indexer progress per chain and factory combination';

-- Verification
DO $$
BEGIN
    -- Verify columns exist
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'indexer_state' AND column_name = 'start_block'
    ) AND EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'indexer_state' AND column_name = 'factory_address'
    ) THEN
        RAISE NOTICE '✅ Migration 029 completed successfully: added start_block and factory_address columns to indexer_state';
    ELSE
        RAISE EXCEPTION 'Migration 029 failed: missing required columns in indexer_state table';
    END IF;
END $$;

COMMIT;