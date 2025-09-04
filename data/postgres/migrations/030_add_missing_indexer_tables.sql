-- Migration 030: Add missing tables required by the indexer
-- Creates enabled_tokens, price_requests, and token_prices tables

BEGIN;

-- ============================================================================
-- ENABLED_TOKENS TABLE
-- ============================================================================
-- Track which tokens are enabled for auctions
CREATE TABLE IF NOT EXISTS enabled_tokens (
    id SERIAL PRIMARY KEY,
    auction_address VARCHAR(100) NOT NULL,
    chain_id INTEGER NOT NULL DEFAULT 1,
    from_token VARCHAR(100) NOT NULL,
    enabled_at TIMESTAMP WITH TIME ZONE NOT NULL,
    block_number BIGINT NOT NULL,
    transaction_hash VARCHAR(100) NOT NULL,
    log_index INTEGER NOT NULL,
    
    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Prevent duplicate entries
    UNIQUE (auction_address, chain_id, from_token)
);

-- Indexes for enabled_tokens
CREATE INDEX IF NOT EXISTS idx_enabled_tokens_auction ON enabled_tokens (auction_address, chain_id);
CREATE INDEX IF NOT EXISTS idx_enabled_tokens_token ON enabled_tokens (from_token, chain_id);
CREATE INDEX IF NOT EXISTS idx_enabled_tokens_enabled_at ON enabled_tokens (enabled_at);

-- ============================================================================
-- PRICE_REQUESTS TABLE  
-- ============================================================================
-- Track price requests for token pricing
CREATE TABLE IF NOT EXISTS price_requests (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    token_address VARCHAR(100) NOT NULL,
    request_type VARCHAR(50) NOT NULL DEFAULT 'take',
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    
    -- Request timing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    txn_timestamp BIGINT, -- Unix timestamp from the originating transaction
    
    -- Request configuration
    price_source VARCHAR(50) DEFAULT 'all', -- which price service to use
    retries INTEGER DEFAULT 0,
    last_error TEXT,
    
    -- Prevent duplicate requests
    UNIQUE (chain_id, block_number, token_address, request_type)
);

-- Indexes for price_requests
CREATE INDEX IF NOT EXISTS idx_price_requests_status ON price_requests (status);
CREATE INDEX IF NOT EXISTS idx_price_requests_created ON price_requests (created_at);
CREATE INDEX IF NOT EXISTS idx_price_requests_chain_token ON price_requests (chain_id, token_address);
CREATE INDEX IF NOT EXISTS idx_price_requests_txn_timestamp ON price_requests (txn_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_price_requests_price_source ON price_requests (price_source);

-- ============================================================================
-- TOKEN_PRICES TABLE
-- ============================================================================
-- Store token prices from various sources
CREATE TABLE IF NOT EXISTS token_prices (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    token_address VARCHAR(100) NOT NULL,
    block_number BIGINT NOT NULL,
    
    -- Price data
    price_usd DECIMAL(20,8), -- Price in USD
    source VARCHAR(50) NOT NULL, -- coingecko, defillama, 1inch, etc.
    timestamp BIGINT NOT NULL, -- Unix timestamp
    
    -- Request metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    txn_timestamp BIGINT, -- Transaction timestamp that triggered this price request
    
    -- Market data (optional)
    volume_24h DECIMAL(20,8),
    market_cap DECIMAL(20,8),
    
    -- Prevent duplicate entries
    UNIQUE (chain_id, token_address, block_number, source)
);

-- Indexes for token_prices
CREATE INDEX IF NOT EXISTS idx_token_prices_chain_token ON token_prices (chain_id, token_address);
CREATE INDEX IF NOT EXISTS idx_token_prices_timestamp ON token_prices (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_token_prices_block ON token_prices (block_number DESC);
CREATE INDEX IF NOT EXISTS idx_token_prices_source ON token_prices (source);
CREATE INDEX IF NOT EXISTS idx_token_prices_txn_timestamp ON token_prices (txn_timestamp DESC);

-- ============================================================================
-- COMMENTS AND CONSTRAINTS
-- ============================================================================
-- Add helpful comments
COMMENT ON TABLE enabled_tokens IS 'Tracks which tokens are enabled for trading on each auction contract';
COMMENT ON TABLE price_requests IS 'Queue of price requests to be processed by pricing services';
COMMENT ON TABLE token_prices IS 'Historical token prices from various data sources';

COMMENT ON COLUMN price_requests.request_type IS 'Request type: kick, take, backfill, manual, etc.';
COMMENT ON COLUMN price_requests.status IS 'Status: pending, processing, completed, failed, etc.';
COMMENT ON COLUMN price_requests.price_source IS 'Intended price service(s): all, ypm, odos, enso, or comma-separated list';
COMMENT ON COLUMN token_prices.txn_timestamp IS 'Unix timestamp from the blockchain transaction that generated this price request';

-- Add flexible constraints (allow any string values)
ALTER TABLE price_requests ADD CONSTRAINT IF NOT EXISTS price_requests_request_type_check 
    CHECK (request_type IS NOT NULL AND LENGTH(request_type) > 0);
    
ALTER TABLE price_requests ADD CONSTRAINT IF NOT EXISTS price_requests_status_check 
    CHECK (status IS NOT NULL AND LENGTH(status) > 0);

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
DECLARE
    enabled_tokens_exists BOOLEAN;
    price_requests_exists BOOLEAN;
    token_prices_exists BOOLEAN;
BEGIN
    -- Check if tables exist
    SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'enabled_tokens') INTO enabled_tokens_exists;
    SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'price_requests') INTO price_requests_exists;
    SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'token_prices') INTO token_prices_exists;
    
    IF enabled_tokens_exists AND price_requests_exists AND token_prices_exists THEN
        RAISE NOTICE '✅ Migration 030 completed successfully:';
        RAISE NOTICE '  - Created enabled_tokens table for auction token tracking';
        RAISE NOTICE '  - Created price_requests table for pricing service queue';
        RAISE NOTICE '  - Created token_prices table for historical price storage';
        RAISE NOTICE '  - Added performance indexes and constraints';
        RAISE NOTICE '  - Added comprehensive documentation';
    ELSE
        RAISE EXCEPTION 'Migration 030 failed: some tables were not created successfully';
    END IF;
END $$;

COMMIT;