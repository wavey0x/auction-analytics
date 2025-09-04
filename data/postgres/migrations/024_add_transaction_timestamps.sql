-- Migration 024: Add transaction timestamps to price_requests and token_prices
-- This enables time-based processing where quote APIs only process recent transactions

BEGIN;

-- Check if tables exist before modifying them
DO $$
BEGIN
    -- Handle price_requests table if it exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'price_requests') THEN
        -- Add transaction timestamp to price_requests table
        ALTER TABLE price_requests ADD COLUMN IF NOT EXISTS txn_timestamp BIGINT;
        
        -- Add price source specification to allow targeted processing
        ALTER TABLE price_requests ADD COLUMN IF NOT EXISTS price_source VARCHAR(50) DEFAULT 'all';
        
        -- Add indexes for efficient timestamp-based queries
        CREATE INDEX IF NOT EXISTS idx_price_requests_txn_timestamp ON price_requests(txn_timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_price_requests_price_source ON price_requests(price_source);
        
        -- Add comments to document the new fields
        COMMENT ON COLUMN price_requests.txn_timestamp IS 'Unix timestamp from the originating blockchain transaction (kick/take)';
        COMMENT ON COLUMN price_requests.price_source IS 'Intended price service(s): all, ypm, odos, enso, or comma-separated list';
        
        RAISE NOTICE '✅ Updated price_requests table with transaction timestamps';
    ELSE
        RAISE NOTICE '⚠️  price_requests table does not exist - skipping price_requests modifications';
    END IF;
    
    -- Handle token_prices table if it exists  
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'token_prices') THEN
        -- Add transaction timestamp to token_prices table
        ALTER TABLE token_prices ADD COLUMN IF NOT EXISTS txn_timestamp BIGINT;
        
        -- Add indexes for efficient timestamp-based queries
        CREATE INDEX IF NOT EXISTS idx_token_prices_txn_timestamp ON token_prices(txn_timestamp DESC);
        
        -- Add comments to document the new fields
        COMMENT ON COLUMN token_prices.txn_timestamp IS 'Unix timestamp from the blockchain transaction that generated this price request';
        
        -- Update existing token_prices to inherit txn_timestamp from their corresponding price_requests
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'price_requests') THEN
            UPDATE token_prices 
            SET txn_timestamp = (
                SELECT EXTRACT(EPOCH FROM pr.created_at)::BIGINT
                FROM price_requests pr 
                WHERE pr.chain_id = token_prices.chain_id 
                  AND pr.block_number = token_prices.block_number 
                  AND pr.token_address = token_prices.token_address
                LIMIT 1
            )
            WHERE txn_timestamp IS NULL;
        END IF;
        
        -- For token_prices without corresponding price_requests, use their own created_at timestamp
        UPDATE token_prices 
        SET txn_timestamp = EXTRACT(EPOCH FROM created_at)::BIGINT
        WHERE txn_timestamp IS NULL;
        
        RAISE NOTICE '✅ Updated token_prices table with transaction timestamps';
    ELSE
        RAISE NOTICE '⚠️  token_prices table does not exist - skipping token_prices modifications';
    END IF;
    
    RAISE NOTICE '✅ Transaction timestamp migration completed successfully';
END $$;

COMMIT;