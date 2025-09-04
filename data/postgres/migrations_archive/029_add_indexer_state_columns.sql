-- Migration 029: Add missing columns to indexer_state table and fix primary key
-- The custom indexer expects start_block, factory_address, and factory_type columns
-- Also needs composite primary key (chain_id, factory_address)

BEGIN;

-- Add missing columns to indexer_state table
ALTER TABLE indexer_state ADD COLUMN IF NOT EXISTS start_block INTEGER DEFAULT 0;
ALTER TABLE indexer_state ADD COLUMN IF NOT EXISTS factory_address VARCHAR(100);
ALTER TABLE indexer_state ADD COLUMN IF NOT EXISTS factory_type VARCHAR(10);

-- Update primary key if needed
DO $$
BEGIN
    -- Check if current primary key is just chain_id
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_name = 'indexer_state' 
        AND tc.constraint_type = 'PRIMARY KEY'
        AND kcu.column_name = 'chain_id'
        AND NOT EXISTS (
            SELECT 1 FROM information_schema.key_column_usage kcu2 
            WHERE kcu2.constraint_name = tc.constraint_name 
            AND kcu2.column_name = 'factory_address'
        )
    ) THEN
        -- Drop existing primary key constraint
        ALTER TABLE indexer_state DROP CONSTRAINT indexer_state_pkey;
        
        -- Add composite primary key
        ALTER TABLE indexer_state ADD CONSTRAINT indexer_state_pkey 
            PRIMARY KEY (chain_id, factory_address);
        
        RAISE NOTICE 'Updated primary key to (chain_id, factory_address)';
    END IF;
END $$;

-- Create performance indexes
CREATE INDEX IF NOT EXISTS idx_indexer_state_chain_factory ON indexer_state (chain_id, factory_address);
CREATE INDEX IF NOT EXISTS idx_indexer_state_updated ON indexer_state (updated_at);
CREATE INDEX IF NOT EXISTS idx_indexer_state_factory_type ON indexer_state (factory_type);

-- Add comments to document the columns
COMMENT ON COLUMN indexer_state.start_block IS 'Starting block number for this factory indexer';
COMMENT ON COLUMN indexer_state.factory_address IS 'Factory contract address being indexed';
COMMENT ON COLUMN indexer_state.factory_type IS 'Factory type: legacy or modern';
COMMENT ON TABLE indexer_state IS 'Tracks indexer progress per factory per blockchain network';

-- Verification
DO $$
DECLARE
    missing_columns TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Check for missing columns
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'indexer_state' AND column_name = 'start_block') THEN
        missing_columns := array_append(missing_columns, 'start_block');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'indexer_state' AND column_name = 'factory_address') THEN
        missing_columns := array_append(missing_columns, 'factory_address');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'indexer_state' AND column_name = 'factory_type') THEN
        missing_columns := array_append(missing_columns, 'factory_type');
    END IF;
    
    IF array_length(missing_columns, 1) > 0 THEN
        RAISE EXCEPTION 'Migration 029 failed: missing columns: %', array_to_string(missing_columns, ', ');
    ELSE
        RAISE NOTICE '✅ Migration 029 completed successfully:';
        RAISE NOTICE '  - Added start_block, factory_address, and factory_type columns';
        RAISE NOTICE '  - Updated primary key to (chain_id, factory_address)';
        RAISE NOTICE '  - Created performance indexes';
    END IF;
END $$;

COMMIT;