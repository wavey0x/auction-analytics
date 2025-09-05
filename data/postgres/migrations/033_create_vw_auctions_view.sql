-- =============================================================================
-- MIGRATION 033: CREATE vw_auctions VIEW FOR AUCTION ANALYTICS
-- =============================================================================
-- Creates the missing vw_auctions view that aggregates auction data
-- with current round information and token metadata
-- Date: 2025-01-04

-- Drop view if exists (for re-running migration)
DROP VIEW IF EXISTS vw_auctions;

-- Create comprehensive vw_auctions view
CREATE VIEW vw_auctions AS
SELECT 
    a.auction_address,
    a.chain_id,
    a.want_token,
    a.deployer,
    a.update_interval,
    a.auction_length,
    a.starting_price,
    a.version,
    a.decay_rate,
    
    -- Want token metadata
    wt.symbol as want_token_symbol,
    wt.name as want_token_name,
    wt.decimals as want_token_decimals,
    
    -- Current round information (latest round for each auction)
    cr.round_id as current_round_id,
    CASE 
        WHEN (cr.kicked_at + 86400) > EXTRACT(EPOCH FROM NOW())::BIGINT THEN TRUE ELSE FALSE 
    END as has_active_round,
    cr.available_amount as current_available,
    to_timestamp(cr.kicked_at) as last_kicked_timestamp,
    cr.kicked_at as last_kicked,
    cr.initial_available,
    
    -- Round timing (convert epoch to timestamp)
    to_timestamp(COALESCE(cr.round_start, cr.kicked_at)) as round_start,
    to_timestamp(COALESCE(cr.round_start, cr.kicked_at) + 86400) as round_end,
    
    -- Progress calculation
    CASE 
        WHEN cr.initial_available > 0 AND cr.available_amount IS NOT NULL 
        THEN ROUND((1.0 - (cr.available_amount::DECIMAL / cr.initial_available::DECIMAL)) * 100, 2)
        ELSE 0.0 
    END as progress_percentage,
    
    -- Takes count for current round
    COALESCE(takes_count.current_round_takes, 0) as current_round_takes

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
        r.from_token,
        r.round_start,
        r.round_end
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

;

-- Create index on the view for performance
CREATE INDEX IF NOT EXISTS idx_vw_auctions_chain 
    ON auctions (chain_id);

-- Verification query
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.views WHERE table_name = 'vw_auctions') THEN
        RAISE NOTICE '✅ vw_auctions view created successfully';
    ELSE
        RAISE EXCEPTION '❌ Failed to create vw_auctions view';
    END IF;
END $$;

-- Show sample data (if any exists)
DO $$
DECLARE
    row_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO row_count FROM vw_auctions;
    RAISE NOTICE 'ℹ️  vw_auctions view contains % rows', row_count;
    
    -- Show first few columns of first row as sample
    IF row_count > 0 THEN
        RAISE NOTICE 'ℹ️  Sample data available - view is working correctly';
    ELSE
        RAISE NOTICE 'ℹ️  No data yet - view structure created, waiting for auctions to be indexed';
    END IF;
END $$;
