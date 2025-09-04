-- =============================================================================
-- PRODUCTION FIX: CREATE MISSING vw_auctions VIEW
-- =============================================================================
-- This script creates the missing vw_auctions view that the API requires
-- Run this on your production database to fix the error:
-- "relation 'vw_auctions' does not exist"
--
-- Usage:
--   psql $DATABASE_URL -f fix_production_vw_auctions.sql
--
-- Date: 2025-01-04
-- Issue: Missing vw_auctions view causing production API failures

\echo 'Creating missing vw_auctions view for production database...'

-- Drop view if exists (for re-running migration)
DROP VIEW IF EXISTS vw_auctions;

-- Create comprehensive vw_auctions view
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

-- Create index on the base table for performance
CREATE INDEX IF NOT EXISTS idx_vw_auctions_chain_active 
    ON auctions (chain_id) 
    WHERE EXISTS (
        SELECT 1 FROM rounds r 
        WHERE LOWER(r.auction_address) = LOWER(auctions.auction_address) 
            AND r.chain_id = auctions.chain_id 
            AND r.is_active = true
    );

-- Verification
DO $$ 
DECLARE
    row_count INTEGER;
BEGIN
    -- Check if view was created
    IF EXISTS (SELECT 1 FROM information_schema.views WHERE table_name = 'vw_auctions') THEN
        RAISE NOTICE '✅ vw_auctions view created successfully';
        
        -- Count rows
        EXECUTE 'SELECT COUNT(*) FROM vw_auctions' INTO row_count;
        RAISE NOTICE 'ℹ️  vw_auctions view contains % rows', row_count;
        
        IF row_count > 0 THEN
            RAISE NOTICE '✅ Production database should now work correctly';
        ELSE
            RAISE NOTICE 'ℹ️  No auction data found - view is ready for when auctions are added';
        END IF;
    ELSE
        RAISE EXCEPTION '❌ Failed to create vw_auctions view';
    END IF;
END $$;

\echo 'Production fix completed successfully!'
\echo 'Your API should now work without the "vw_auctions does not exist" error.'