-- =============================================================================
-- COMPLETE AUCTION ANALYTICS DATABASE SCHEMA
-- =============================================================================
-- One-shot schema that includes all tables, indexes, and seed data
-- Works with or without TimescaleDB, supports all deployment modes

-- Enable TimescaleDB extension for time-series data (optional)
DO $$ 
BEGIN
    CREATE EXTENSION IF NOT EXISTS timescaledb;
    RAISE NOTICE '✅ TimescaleDB extension enabled for optimal performance';
EXCEPTION 
    WHEN others THEN
        RAISE NOTICE '⚠️  TimescaleDB not available, using standard PostgreSQL (still works fine)';
END $$;

-- =============================================================================
-- TOKEN METADATA CACHE
-- =============================================================================
CREATE TABLE tokens (
    id SERIAL PRIMARY KEY,
    address VARCHAR(100) NOT NULL,
    symbol VARCHAR(50),
    name VARCHAR(200),
    decimals INTEGER,
    chain_id INTEGER NOT NULL DEFAULT 1,
    
    -- Metadata
    first_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    timestamp BIGINT DEFAULT EXTRACT(EPOCH FROM NOW())::BIGINT,
    
    UNIQUE (address, chain_id)
);

-- Indexes for tokens table
CREATE INDEX idx_tokens_address ON tokens (address);
CREATE INDEX idx_tokens_chain_id ON tokens (chain_id);
CREATE INDEX idx_tokens_timestamp ON tokens (timestamp DESC);
CREATE INDEX idx_tokens_lower_address_chain ON tokens (LOWER(address), chain_id);

-- =============================================================================
-- AUCTIONS - MAIN AUCTION CONTRACTS TABLE
-- =============================================================================
CREATE TABLE auctions (
    auction_address VARCHAR(100) NOT NULL,
    chain_id INTEGER NOT NULL DEFAULT 1,
    
    -- Auction parameters
    price_update_interval INTEGER NOT NULL DEFAULT 36,
    step_decay DECIMAL(30,0), -- Legacy RAY precision field
    step_decay_rate DECIMAL(30,0), -- Decay rate per step (RAY format)
    auction_length INTEGER DEFAULT 3600, -- Duration in seconds
    starting_price DECIMAL(30,0), -- Fixed starting price in wei, NULL for dynamic
    
    -- Human-readable fields for indexer compatibility
    version VARCHAR(20) DEFAULT '0.1.0', -- Contract version: 0.0.1 (legacy) or 0.1.0 (modern)
    decay_rate DECIMAL(10,4) DEFAULT 0.005, -- Human-readable decay rate (0.005 = 0.5%)
    update_interval INTEGER DEFAULT 36, -- Update interval in seconds
    
    -- Token addresses
    want_token VARCHAR(100),
    
    -- Governance info
    deployer VARCHAR(100),
    receiver VARCHAR(100),
    governance VARCHAR(100),
    
    -- Discovery metadata
    discovered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    timestamp BIGINT, -- Unix timestamp when auction was deployed (from block timestamp)
    factory_address VARCHAR(100),
    
    PRIMARY KEY (auction_address, chain_id)
);

-- Indexes for auctions table
CREATE INDEX idx_auctions_deployer ON auctions (deployer);
CREATE INDEX idx_auctions_factory ON auctions (factory_address);
CREATE INDEX idx_auctions_chain ON auctions (chain_id);
CREATE INDEX idx_auctions_timestamp ON auctions (timestamp DESC);
CREATE INDEX idx_auctions_version ON auctions (version);

-- =============================================================================
-- ROUNDS - AUCTION ROUND TRACKING
-- =============================================================================
CREATE TABLE rounds (
    auction_address VARCHAR(100) NOT NULL,
    chain_id INTEGER NOT NULL DEFAULT 1,
    round_id INTEGER NOT NULL, -- Incremental per auction: 1, 2, 3...
    from_token VARCHAR(100) NOT NULL,
    
    -- Round data
    kicked_at TIMESTAMP WITH TIME ZONE NOT NULL,
    initial_available NUMERIC(78,18) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    
    -- Current state
    current_price DECIMAL(30,0),
    available_amount NUMERIC(78,18),
    time_remaining INTEGER,
    seconds_elapsed INTEGER DEFAULT 0,
    
    -- Statistics
    total_volume_sold NUMERIC(78,18) DEFAULT 0,
    progress_percentage DECIMAL(5,2) DEFAULT 0,
    
    -- Block data
    block_number BIGINT NOT NULL,
    transaction_hash VARCHAR(100) NOT NULL,
    
    PRIMARY KEY (auction_address, chain_id, round_id)
);

-- Indexes for rounds table
CREATE INDEX idx_rounds_active ON rounds (is_active);
CREATE INDEX idx_rounds_kicked_at ON rounds (kicked_at DESC);
CREATE INDEX idx_rounds_chain ON rounds (chain_id);
CREATE INDEX idx_rounds_from_token ON rounds (from_token);
CREATE INDEX idx_rounds_auction_chain_available_pos ON rounds (auction_address, chain_id) WHERE available_amount > 0;

-- =============================================================================
-- TAKES - INDIVIDUAL AUCTION TAKES
-- =============================================================================
CREATE TABLE takes (
    take_id VARCHAR(200) NOT NULL, -- Format: {auction}-{roundId}-{takeSeq}
    auction_address VARCHAR(100) NOT NULL,
    chain_id INTEGER NOT NULL DEFAULT 1,
    round_id INTEGER NOT NULL,
    take_seq INTEGER NOT NULL, -- Sequence within round: 1, 2, 3...
    
    -- Take data
    taker VARCHAR(100) NOT NULL,
    from_token VARCHAR(100) NOT NULL,
    to_token VARCHAR(100) NOT NULL,
    amount_taken NUMERIC(78,18) NOT NULL, -- Human-readable amount
    amount_paid NUMERIC(78,18) NOT NULL, -- Human-readable amount
    price NUMERIC(78,18) NOT NULL, -- Human-readable price
    
    -- Timing
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    seconds_from_round_start INTEGER NOT NULL,
    
    -- Gas tracking
    gas_price NUMERIC(78,18),
    base_fee NUMERIC(78,18),
    priority_fee NUMERIC(78,18),
    gas_used BIGINT,
    transaction_fee_eth NUMERIC(78,18),
    
    -- Block data
    block_number BIGINT NOT NULL,
    transaction_hash VARCHAR(100) NOT NULL,
    log_index INTEGER NOT NULL,
    
    PRIMARY KEY (take_id, timestamp)
);

-- Indexes for takes table
CREATE INDEX idx_takes_timestamp ON takes (timestamp DESC);
CREATE INDEX idx_takes_chain ON takes (chain_id);
CREATE INDEX idx_takes_auction_chain ON takes (auction_address, chain_id);
CREATE INDEX idx_takes_round ON takes (auction_address, chain_id, round_id);
CREATE INDEX idx_takes_taker ON takes (taker);
CREATE INDEX idx_takes_tx_hash ON takes (transaction_hash);

-- Make takes a hypertable for time-series optimization (if TimescaleDB available)
DO $$
BEGIN
    PERFORM create_hypertable('takes', 'timestamp', if_not_exists => TRUE);
    RAISE NOTICE '✅ TimescaleDB hypertable created for takes table';
EXCEPTION 
    WHEN others THEN
        RAISE NOTICE 'ℹ️  Using regular PostgreSQL table for takes (TimescaleDB not available)';
END $$;

-- =============================================================================
-- INDEXER STATE TRACKING
-- =============================================================================
CREATE TABLE indexer_state (
    chain_id INTEGER NOT NULL,
    factory_address VARCHAR(100) NOT NULL,
    factory_type VARCHAR(10), -- 'legacy' or 'modern'
    last_indexed_block INTEGER NOT NULL DEFAULT 0,
    start_block INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    PRIMARY KEY (chain_id, factory_address)
);

-- Indexes for indexer_state
CREATE INDEX idx_indexer_state_updated ON indexer_state (updated_at);
CREATE INDEX idx_indexer_state_factory_type ON indexer_state (factory_type);

-- =============================================================================
-- ENABLED TOKENS - AUCTION TOKEN TRACKING
-- =============================================================================
CREATE TABLE enabled_tokens (
    id SERIAL PRIMARY KEY,
    auction_address VARCHAR(100) NOT NULL,
    chain_id INTEGER NOT NULL DEFAULT 1,
    from_token VARCHAR(100) NOT NULL,
    enabled_at TIMESTAMP WITH TIME ZONE NOT NULL,
    block_number BIGINT NOT NULL,
    transaction_hash VARCHAR(100) NOT NULL,
    log_index INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE (auction_address, chain_id, from_token)
);

-- Indexes for enabled_tokens
CREATE INDEX idx_enabled_tokens_auction ON enabled_tokens (auction_address, chain_id);
CREATE INDEX idx_enabled_tokens_token ON enabled_tokens (from_token, chain_id);
CREATE INDEX idx_enabled_tokens_enabled_at ON enabled_tokens (enabled_at);

-- =============================================================================
-- PRICE REQUESTS - PRICING SERVICE QUEUE
-- =============================================================================
CREATE TABLE price_requests (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    token_address VARCHAR(100) NOT NULL,
    request_type VARCHAR(50) NOT NULL DEFAULT 'take',
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    
    -- Request timing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    txn_timestamp BIGINT,
    
    -- Request configuration
    price_source VARCHAR(50) DEFAULT 'all',
    retries INTEGER DEFAULT 0,
    last_error TEXT,
    
    UNIQUE (chain_id, block_number, token_address, request_type)
);

-- Indexes for price_requests
CREATE INDEX idx_price_requests_status ON price_requests (status);
CREATE INDEX idx_price_requests_created ON price_requests (created_at);
CREATE INDEX idx_price_requests_chain_token ON price_requests (chain_id, token_address);
CREATE INDEX idx_price_requests_txn_timestamp ON price_requests (txn_timestamp DESC);
CREATE INDEX idx_price_requests_price_source ON price_requests (price_source);

-- =============================================================================
-- TOKEN PRICES - HISTORICAL PRICE STORAGE
-- =============================================================================
CREATE TABLE token_prices (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    token_address VARCHAR(100) NOT NULL,
    block_number BIGINT NOT NULL,
    
    -- Price data
    price_usd DECIMAL(20,8),
    source VARCHAR(50) NOT NULL,
    timestamp BIGINT NOT NULL,
    
    -- Request metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    txn_timestamp BIGINT,
    
    -- Market data
    volume_24h DECIMAL(20,8),
    market_cap DECIMAL(20,8),
    
    UNIQUE (chain_id, token_address, block_number, source)
);

-- Indexes for token_prices
CREATE INDEX idx_token_prices_chain_token ON token_prices (chain_id, token_address);
CREATE INDEX idx_token_prices_timestamp ON token_prices (timestamp DESC);
CREATE INDEX idx_token_prices_block ON token_prices (block_number DESC);
CREATE INDEX idx_token_prices_source ON token_prices (source);
CREATE INDEX idx_token_prices_txn_timestamp ON token_prices (txn_timestamp DESC);

-- =============================================================================
-- OUTBOX EVENTS - EVENT PUBLISHING
-- =============================================================================
CREATE TABLE outbox_events (
    id BIGSERIAL PRIMARY KEY,
    
    -- Event metadata
    type VARCHAR(50) NOT NULL,
    chain_id INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    tx_hash VARCHAR(100) NOT NULL,
    log_index INTEGER NOT NULL,
    
    -- Event data
    auction_address VARCHAR(100),
    round_id INTEGER,
    from_token VARCHAR(100),
    want_token VARCHAR(100),
    timestamp BIGINT NOT NULL,
    
    -- Payload for event-specific data
    payload_json JSONB NOT NULL DEFAULT '{}',
    
    -- Idempotency and versioning
    uniq VARCHAR(200) NOT NULL,
    ver INTEGER NOT NULL DEFAULT 1,
    
    -- Publishing status
    published_at TIMESTAMPTZ,
    retries INTEGER DEFAULT 0,
    last_error TEXT,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE (uniq)
);

-- Indexes for outbox_events
CREATE INDEX idx_outbox_unpublished ON outbox_events (id) WHERE published_at IS NULL;
CREATE INDEX idx_outbox_chain_block ON outbox_events (chain_id, block_number);
CREATE INDEX idx_outbox_created ON outbox_events (created_at);
CREATE INDEX idx_outbox_retries ON outbox_events (retries) WHERE published_at IS NULL AND retries > 3;

-- =============================================================================
-- FUNCTIONS AND TRIGGERS
-- =============================================================================

-- Function to update round statistics when takes happen
CREATE OR REPLACE FUNCTION update_round_statistics()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE rounds 
    SET 
        total_volume_sold = total_volume_sold + NEW.amount_taken,
        progress_percentage = LEAST(100.0, 
            ((total_volume_sold + NEW.amount_taken) * 100.0) / GREATEST(initial_available, 1)
        ),
        available_amount = GREATEST(0, initial_available - (total_volume_sold + NEW.amount_taken))
    WHERE 
        auction_address = NEW.auction_address 
        AND chain_id = NEW.chain_id 
        AND round_id = NEW.round_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update round statistics on new takes
CREATE TRIGGER trigger_update_round_statistics
    AFTER INSERT ON takes
    FOR EACH ROW
    EXECUTE FUNCTION update_round_statistics();

-- =============================================================================
-- VIEWS FOR ANALYTICS
-- =============================================================================

-- View for enhanced takes with full context (simplified version)
CREATE OR REPLACE VIEW vw_takes_enriched AS
SELECT 
    t.take_id,
    t.auction_address,
    t.chain_id,
    t.round_id,
    t.take_seq,
    t.taker,
    t.from_token,
    t.to_token,
    t.amount_taken,
    t.amount_paid,
    t.price,
    t.timestamp,
    t.seconds_from_round_start,
    t.block_number,
    t.transaction_hash,
    t.log_index,
    t.gas_price,
    t.base_fee,
    t.priority_fee,
    t.gas_used,
    t.transaction_fee_eth,
    -- Round information
    r.kicked_at as round_kicked_at,
    r.initial_available as round_initial_available,
    -- Token metadata
    tf.symbol as from_token_symbol,
    tf.name as from_token_name,
    tf.decimals as from_token_decimals,
    tt.symbol as to_token_symbol,
    tt.name as to_token_name,
    tt.decimals as to_token_decimals,
    -- Price information (set to NULL - will be populated by pricing services)
    NULL::NUMERIC as from_token_price_usd,
    NULL::NUMERIC as to_token_price_usd,
    NULL::NUMERIC as amount_taken_usd,
    NULL::NUMERIC as amount_paid_usd,
    NULL::NUMERIC as price_differential_usd,
    NULL::NUMERIC as price_differential_percent,
    NULL::NUMERIC as transaction_fee_usd
FROM takes t
LEFT JOIN rounds r ON t.auction_address = r.auction_address 
                  AND t.chain_id = r.chain_id 
                  AND t.round_id = r.round_id
LEFT JOIN tokens tf ON LOWER(tf.address) = LOWER(t.from_token) 
                   AND tf.chain_id = t.chain_id
LEFT JOIN tokens tt ON LOWER(tt.address) = LOWER(t.to_token) 
                   AND tt.chain_id = t.chain_id;

-- =============================================================================
-- INITIAL SEED DATA
-- =============================================================================

-- Insert common tokens for reference across different chains
INSERT INTO tokens (address, symbol, name, decimals, chain_id, timestamp) VALUES
-- Ethereum Mainnet (Chain ID 1)
('0x0000000000000000000000000000000000000000', 'ETH', 'Ethereum', 18, 1, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0xA0b86a33E6441b8C87C83e4F8E3FBcE66A6F8cDf', 'USDC', 'USD Coin', 6, 1, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', 'WETH', 'Wrapped Ether', 18, 1, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0xdAC17F958D2ee523a2206206994597C13D831ec7', 'USDT', 'Tether USD', 6, 1, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599', 'WBTC', 'Wrapped Bitcoin', 8, 1, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0x6B175474E89094C44Da98b954EedeAC495271d0F', 'DAI', 'Dai Stablecoin', 18, 1, EXTRACT(EPOCH FROM NOW())::BIGINT),

-- Polygon (Chain ID 137)
('0x0000000000000000000000000000000000000000', 'MATIC', 'Polygon', 18, 137, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174', 'USDC', 'USD Coin', 6, 137, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619', 'WETH', 'Wrapped Ether', 18, 137, EXTRACT(EPOCH FROM NOW())::BIGINT),

-- Arbitrum (Chain ID 42161)
('0x0000000000000000000000000000000000000000', 'ETH', 'Ethereum', 18, 42161, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8', 'USDC', 'USD Coin', 6, 42161, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0x82aF49447D8a07e3bd95BD0d56f35241523fBab1', 'WETH', 'Wrapped Ether', 18, 42161, EXTRACT(EPOCH FROM NOW())::BIGINT),

-- Optimism (Chain ID 10)
('0x0000000000000000000000000000000000000000', 'ETH', 'Ethereum', 18, 10, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0x7F5c764cBc14f9669B88837ca1490cCa17c31607', 'USDC', 'USD Coin', 6, 10, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0x4200000000000000000000000000000000000006', 'WETH', 'Wrapped Ether', 18, 10, EXTRACT(EPOCH FROM NOW())::BIGINT),

-- Base (Chain ID 8453)
('0x0000000000000000000000000000000000000000', 'ETH', 'Ethereum', 18, 8453, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913', 'USDC', 'USD Coin', 6, 8453, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0x4200000000000000000000000000000000000006', 'WETH', 'Wrapped Ether', 18, 8453, EXTRACT(EPOCH FROM NOW())::BIGINT),

-- Anvil/Local testnet (Chain ID 31337)
('0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512', 'USDC', 'USD Coin', 6, 31337, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0', 'USDT', 'Tether USD', 6, 31337, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9', 'WETH', 'Wrapped Ether', 18, 31337, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9', 'WBTC', 'Wrapped Bitcoin', 8, 31337, EXTRACT(EPOCH FROM NOW())::BIGINT),
('0x5FC8d32690cc91D4c39d9d3abcBD16989F875707', 'DAI', 'Dai Stablecoin', 18, 31337, EXTRACT(EPOCH FROM NOW())::BIGINT)
ON CONFLICT (address, chain_id) DO NOTHING;

-- =============================================================================
-- VIEWS - CONSOLIDATED AUCTION DATA
-- =============================================================================

-- vw_auctions: Comprehensive view aggregating auction data with current round info
CREATE VIEW vw_auctions AS
SELECT 
    a.auction_address,
    a.chain_id,
    a.want_token,
    a.deployer,
    a.price_update_interval,
    a.auction_length,
    a.starting_price,
    a.version,
    a.decay_rate,
    a.update_interval,
    a.discovered_at,
    
    -- Want token metadata
    wt.symbol as want_token_symbol,
    wt.name as want_token_name,
    wt.decimals as want_token_decimals,
    
    -- Current round information (latest round for each auction)
    cr.round_id as current_round_id,
    cr.is_active as has_active_round,
    cr.available_amount as current_available,
    cr.kicked_at as last_kicked_timestamp,
    EXTRACT(EPOCH FROM cr.kicked_at)::BIGINT as last_kicked,
    cr.initial_available,
    
    -- Round timing
    cr.kicked_at as round_start,
    CASE 
        WHEN cr.kicked_at IS NOT NULL AND a.auction_length IS NOT NULL 
        THEN cr.kicked_at + INTERVAL '1 second' * a.auction_length
        ELSE NULL 
    END as round_end,
    
    -- Progress calculation
    CASE 
        WHEN cr.initial_available > 0 AND cr.available_amount IS NOT NULL 
        THEN ROUND((1.0 - (cr.available_amount::DECIMAL / cr.initial_available::DECIMAL)) * 100, 2)
        ELSE 0.0 
    END as progress_percentage,
    
    -- Takes count for current round
    COALESCE(takes_count.current_round_takes, 0) as current_round_takes,
    
    -- From tokens JSON (array of enabled tokens)
    from_tokens_agg.from_tokens_json
    
FROM auctions a

-- Join want token metadata
LEFT JOIN tokens wt 
    ON LOWER(a.want_token) = LOWER(wt.address) 
    AND a.chain_id = wt.chain_id

-- Join current round (most recent round for each auction)
LEFT JOIN LATERAL (
    SELECT 
        r.round_id,
        r.kicked_at,
        r.initial_available,
        r.available_amount,
        r.is_active,
        r.from_token
    FROM rounds r
    WHERE LOWER(r.auction_address) = LOWER(a.auction_address) 
        AND r.chain_id = a.chain_id
    ORDER BY r.round_id DESC
    LIMIT 1
) cr ON true

-- Count takes for current round
LEFT JOIN LATERAL (
    SELECT COUNT(*) as current_round_takes
    FROM takes t
    WHERE LOWER(t.auction_address) = LOWER(a.auction_address) 
        AND t.chain_id = a.chain_id
        AND t.round_id = cr.round_id
) takes_count ON true

-- Aggregate enabled from_tokens into JSON array
LEFT JOIN LATERAL (
    SELECT 
        COALESCE(
            json_agg(
                json_build_object(
                    'address', et.from_token,
                    'symbol', COALESCE(ft.symbol, 'Unknown'),
                    'name', COALESCE(ft.name, 'Unknown'),
                    'decimals', COALESCE(ft.decimals, 18),
                    'chain_id', et.chain_id
                )
                ORDER BY et.enabled_at
            ), 
            '[]'::json
        ) as from_tokens_json
    FROM enabled_tokens et
    LEFT JOIN tokens ft 
        ON LOWER(et.from_token) = LOWER(ft.address) 
        AND et.chain_id = ft.chain_id
    WHERE LOWER(et.auction_address) = LOWER(a.auction_address)
        AND et.chain_id = a.chain_id
) from_tokens_agg ON true;

-- Performance index for the view
CREATE INDEX IF NOT EXISTS idx_vw_auctions_chain_active 
    ON auctions (chain_id) 
    WHERE EXISTS (
        SELECT 1 FROM rounds r 
        WHERE LOWER(r.auction_address) = LOWER(auctions.auction_address) 
            AND r.chain_id = auctions.chain_id 
            AND r.is_active = true
    );

-- =============================================================================
-- COMPLETION MESSAGE
-- =============================================================================
DO $$
DECLARE
    table_count INTEGER;
    token_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO table_count FROM information_schema.tables WHERE table_schema = 'public';
    SELECT COUNT(*) INTO token_count FROM tokens;
    
    RAISE NOTICE '🎉 AUCTION ANALYTICS DATABASE SETUP COMPLETE!';
    RAISE NOTICE '   📊 Tables created: %', table_count;
    RAISE NOTICE '   🪙 Token seeds loaded: %', token_count;
    RAISE NOTICE '   🔍 Views created: % (includes vw_auctions)', (SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'public');
    RAISE NOTICE '   ⚡ Indexes and triggers: Ready';
    RAISE NOTICE '   🔍 TimescaleDB optimization: %', CASE WHEN EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN 'Enabled' ELSE 'Disabled (optional)' END;
    RAISE NOTICE '';
    RAISE NOTICE '✅ Ready to start indexer and API services!';
END $$;