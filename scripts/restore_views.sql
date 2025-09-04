-- =============================================================================
-- DATABASE VIEWS RESTORATION SCRIPT
-- =============================================================================
-- This script restores all database views that were lost during schema sync.
-- It includes all views required by the API based on migration files and
-- production database analysis.
-- Date: 2025-01-04

BEGIN;

-- =============================================================================
-- 1. ACTIVE_AUCTION_ROUNDS VIEW (from production)
-- =============================================================================
-- Shows currently active auction rounds with calculated time remaining
DROP VIEW IF EXISTS active_auction_rounds CASCADE;

CREATE VIEW active_auction_rounds AS
SELECT 
    ar.auction_address,
    ar.chain_id,
    ar.round_id,
    ar.from_token,
    ar.kicked_at,
    ar.initial_available,
    ar.is_active,
    ar.current_price,
    ar.available_amount,
    ar.time_remaining,
    ar.seconds_elapsed,
    ar.total_volume_sold,
    ar.progress_percentage,
    ar.block_number,
    ar.transaction_hash,
    ahp.want_token,
    ahp.decay_rate_percent,
    ahp.update_interval_minutes,
    ahp.auction_length,
    ahp.step_decay_rate,
    GREATEST(0, ahp.auction_length - EXTRACT(EPOCH FROM NOW() - ar.kicked_at))::INTEGER AS calculated_time_remaining,
    EXTRACT(EPOCH FROM NOW() - ar.kicked_at)::INTEGER AS calculated_seconds_elapsed
FROM rounds ar
JOIN auctions ahp ON ar.auction_address = ahp.auction_address 
    AND ar.chain_id = ahp.chain_id
WHERE ar.is_active = true
ORDER BY ar.kicked_at DESC;

-- =============================================================================
-- 2. RECENT_TAKES VIEW (from production)
-- =============================================================================
-- Shows recent takes with token metadata and round information
DROP VIEW IF EXISTS recent_takes CASCADE;

CREATE VIEW recent_takes AS
SELECT 
    als.take_id,
    als.auction_address,
    als.chain_id,
    als.round_id,
    als.take_seq,
    als.taker,
    als.from_token,
    als.to_token,
    als.amount_taken,
    als.amount_paid,
    als.price,
    als.timestamp,
    als.seconds_from_round_start,
    als.block_number,
    als.transaction_hash,
    als.log_index,
    ar.kicked_at AS round_kicked_at,
    ahp.want_token,
    t1.symbol AS from_token_symbol,
    t1.name AS from_token_name,
    t1.decimals AS from_token_decimals,
    t2.symbol AS to_token_symbol,
    t2.name AS to_token_name,
    t2.decimals AS to_token_decimals
FROM takes als
JOIN rounds ar ON als.auction_address = ar.auction_address 
    AND als.chain_id = ar.chain_id 
    AND als.round_id = ar.round_id
JOIN auctions ahp ON als.auction_address = ahp.auction_address 
    AND als.chain_id = ahp.chain_id
LEFT JOIN tokens t1 ON als.from_token = t1.address 
    AND als.chain_id = t1.chain_id
LEFT JOIN tokens t2 ON als.to_token = t2.address 
    AND als.chain_id = t2.chain_id
ORDER BY als.timestamp DESC;

-- =============================================================================
-- 3. VW_TAKES VIEW (API compatibility - alias for recent_takes)
-- =============================================================================
-- The API references vw_takes which should be the same as recent_takes
DROP VIEW IF EXISTS vw_takes CASCADE;

CREATE VIEW vw_takes AS
SELECT * FROM recent_takes;

-- =============================================================================
-- 4. VW_AUCTIONS VIEW (from migration 033)
-- =============================================================================
-- Comprehensive auction view with current round information and token metadata
DROP VIEW IF EXISTS vw_auctions CASCADE;

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
    
    -- Simplified from_tokens JSON (empty array since enabled_tokens table missing)
    -- TODO: Add enabled_tokens aggregation when table is available
    '[]'::json as from_tokens_json
    
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

-- =============================================================================
-- 5. VW_TAKES_ENRICHED VIEW (from migration 026)
-- =============================================================================
-- Enhanced takes view with USD calculations (if token_prices available)
DROP VIEW IF EXISTS vw_takes_enriched CASCADE;

-- Check if token_prices table exists and create appropriate view
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'token_prices') THEN
        -- Create full view with USD calculations
        EXECUTE '
        CREATE VIEW vw_takes_enriched AS
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
            -- Price information with improved fallback logic
            tp_from.price_usd as from_token_price_usd,
            tp_to.price_usd as to_token_price_usd,
            -- Calculated USD values
            CASE 
                WHEN tp_from.price_usd IS NOT NULL THEN t.amount_taken * tp_from.price_usd
                ELSE NULL
            END as amount_taken_usd,
            CASE 
                WHEN tp_to.price_usd IS NOT NULL THEN t.amount_paid * tp_to.price_usd
                ELSE NULL
            END as amount_paid_usd,
            -- Profit/Loss calculations
            CASE 
                WHEN tp_from.price_usd IS NOT NULL AND tp_to.price_usd IS NOT NULL 
                THEN (t.amount_paid * tp_to.price_usd) - (t.amount_taken * tp_from.price_usd)
                ELSE NULL
            END as price_differential_usd,
            CASE 
                WHEN tp_from.price_usd IS NOT NULL AND tp_to.price_usd IS NOT NULL 
                     AND (t.amount_taken * tp_from.price_usd) > 0
                THEN ((t.amount_paid * tp_to.price_usd) - (t.amount_taken * tp_from.price_usd)) 
                     / (t.amount_taken * tp_from.price_usd) * 100
                ELSE NULL
            END as price_differential_percent,
            -- Transaction fee in USD (for gas analysis)
            CASE 
                WHEN t.transaction_fee_eth IS NOT NULL AND tp_eth.price_usd IS NOT NULL
                THEN t.transaction_fee_eth * tp_eth.price_usd
                ELSE NULL
            END as transaction_fee_usd
        FROM takes t
        -- Join with rounds for additional context
        LEFT JOIN rounds r ON t.auction_address = r.auction_address 
                          AND t.chain_id = r.chain_id 
                          AND t.round_id = r.round_id
        -- Join with token metadata
        LEFT JOIN tokens tf ON LOWER(tf.address) = LOWER(t.from_token) 
                           AND tf.chain_id = t.chain_id
        LEFT JOIN tokens tt ON LOWER(tt.address) = LOWER(t.to_token) 
                           AND tt.chain_id = t.chain_id
        -- Advanced price matching: closest block <= take block, fallback to nearest timestamp
        LEFT JOIN LATERAL (
            SELECT price_usd
            FROM token_prices tp1
            WHERE tp1.chain_id = t.chain_id 
            AND LOWER(tp1.token_address) = LOWER(t.from_token)
            AND tp1.block_number <= t.block_number
            ORDER BY tp1.block_number DESC, ABS(EXTRACT(EPOCH FROM t.timestamp) - tp1.timestamp) ASC
            LIMIT 1
        ) tp_from ON true
        LEFT JOIN LATERAL (
            SELECT price_usd
            FROM token_prices tp2
            WHERE tp2.chain_id = t.chain_id 
            AND LOWER(tp2.token_address) = LOWER(t.to_token)
            AND tp2.block_number <= t.block_number
            ORDER BY tp2.block_number DESC, ABS(EXTRACT(EPOCH FROM t.timestamp) - tp2.timestamp) ASC
            LIMIT 1
        ) tp_to ON true
        -- Get ETH price for gas fee calculations
        LEFT JOIN LATERAL (
            SELECT price_usd
            FROM token_prices tp_eth_inner
            WHERE tp_eth_inner.chain_id = t.chain_id 
            AND (LOWER(tp_eth_inner.token_address) LIKE ''%eth%'' 
                 OR LOWER(tp_eth_inner.token_address) = ''0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'')
            AND tp_eth_inner.block_number <= t.block_number
            ORDER BY tp_eth_inner.block_number DESC
            LIMIT 1
        ) tp_eth ON true';
        
        RAISE NOTICE '✅ Created enhanced vw_takes_enriched with token_prices integration';
    ELSE
        -- Create simplified view without USD calculations
        EXECUTE '
        CREATE VIEW vw_takes_enriched AS
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
            -- USD calculations set to NULL (no price data available)
            NULL::NUMERIC as from_token_price_usd,
            NULL::NUMERIC as to_token_price_usd,
            NULL::NUMERIC as amount_taken_usd,
            NULL::NUMERIC as amount_paid_usd,
            NULL::NUMERIC as price_differential_usd,
            NULL::NUMERIC as price_differential_percent,
            NULL::NUMERIC as transaction_fee_usd
        FROM takes t
        -- Join with rounds for additional context
        LEFT JOIN rounds r ON t.auction_address = r.auction_address 
                          AND t.chain_id = r.chain_id 
                          AND t.round_id = r.round_id
        -- Join with token metadata
        LEFT JOIN tokens tf ON LOWER(tf.address) = LOWER(t.from_token) 
                           AND tf.chain_id = t.chain_id
        LEFT JOIN tokens tt ON LOWER(tt.address) = LOWER(t.to_token) 
                           AND tt.chain_id = t.chain_id';
        
        RAISE NOTICE '⚠️ Created simplified vw_takes_enriched without USD calculations (token_prices table missing)';
    END IF;
END $$;

-- =============================================================================
-- 6. MV_TAKERS_SUMMARY MATERIALIZED VIEW (from migration 026)
-- =============================================================================
-- Pre-calculated taker statistics with rankings and activity metrics
DROP MATERIALIZED VIEW IF EXISTS mv_takers_summary CASCADE;

CREATE MATERIALIZED VIEW mv_takers_summary AS
WITH taker_base_stats AS (
    SELECT 
        t.taker,
        COUNT(*) as total_takes,
        COUNT(DISTINCT t.auction_address) as unique_auctions,
        COUNT(DISTINCT t.chain_id) as unique_chains,
        COALESCE(SUM(t.amount_taken_usd), 0) as total_volume_usd,
        AVG(t.amount_taken_usd) as avg_take_size_usd,
        COALESCE(SUM(t.price_differential_usd), 0) as total_profit_usd,
        AVG(t.price_differential_usd) as avg_profit_per_take_usd,
        MIN(t.timestamp) as first_take,
        MAX(t.timestamp) as last_take,
        ARRAY_AGG(DISTINCT t.chain_id ORDER BY t.chain_id) as active_chains,
        -- Recent activity metrics
        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days') as takes_last_7d,
        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days') as takes_last_30d,
        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days'), 0) as volume_last_7d,
        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days'), 0) as volume_last_30d,
        -- Success rate (positive profit)
        COUNT(*) FILTER (WHERE t.price_differential_usd > 0) as profitable_takes,
        COUNT(*) FILTER (WHERE t.price_differential_usd < 0) as unprofitable_takes
    FROM vw_takes_enriched t
    WHERE t.taker IS NOT NULL
    GROUP BY t.taker
)
SELECT 
    *,
    -- Rankings
    RANK() OVER (ORDER BY total_takes DESC) as rank_by_takes,
    RANK() OVER (ORDER BY total_volume_usd DESC NULLS LAST) as rank_by_volume,
    RANK() OVER (ORDER BY total_profit_usd DESC NULLS LAST) as rank_by_profit,
    -- Success rate calculation
    CASE 
        WHEN (profitable_takes + unprofitable_takes) > 0 
        THEN profitable_takes::DECIMAL / (profitable_takes + unprofitable_takes) * 100
        ELSE NULL
    END as success_rate_percent
FROM taker_base_stats;

-- =============================================================================
-- CREATE INDEXES FOR PERFORMANCE
-- =============================================================================

-- Index for vw_auctions performance
CREATE INDEX IF NOT EXISTS idx_vw_auctions_chain_active 
    ON auctions (chain_id) 
    WHERE EXISTS (
        SELECT 1 FROM rounds r 
        WHERE LOWER(r.auction_address) = LOWER(auctions.auction_address) 
            AND r.chain_id = auctions.chain_id 
            AND r.is_active = true
    );

-- Indexes for mv_takers_summary materialized view
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_takers_summary_taker ON mv_takers_summary(taker);
CREATE INDEX IF NOT EXISTS idx_mv_takers_summary_volume ON mv_takers_summary(total_volume_usd DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_mv_takers_summary_takes ON mv_takers_summary(total_takes DESC);

-- =============================================================================
-- CREATE HELPER FUNCTIONS
-- =============================================================================

-- Function to refresh materialized views
CREATE OR REPLACE FUNCTION refresh_taker_analytics()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_takers_summary;
    RAISE NOTICE 'Refreshed mv_takers_summary materialized view';
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- ADD COMMENTS FOR DOCUMENTATION
-- =============================================================================

COMMENT ON VIEW active_auction_rounds IS 'Shows currently active auction rounds with calculated time remaining and auction parameters';
COMMENT ON VIEW recent_takes IS 'Recent takes with token metadata and round information for API consumption';
COMMENT ON VIEW vw_takes IS 'Alias for recent_takes view (API compatibility)';
COMMENT ON VIEW vw_auctions IS 'Comprehensive auction view with current round information and enabled token metadata';
COMMENT ON VIEW vw_takes_enriched IS 'Enhanced takes view with dynamic USD calculations (if available), token/round context';
COMMENT ON MATERIALIZED VIEW mv_takers_summary IS 'Pre-calculated taker statistics with rankings and activity metrics';

-- =============================================================================
-- VERIFICATION
-- =============================================================================

DO $$
DECLARE
    view_count INTEGER;
    mv_count INTEGER;
    missing_views TEXT[] := ARRAY[]::TEXT[];
    required_views TEXT[] := ARRAY['active_auction_rounds', 'recent_takes', 'vw_takes', 'vw_auctions', 'vw_takes_enriched'];
    required_mvs TEXT[] := ARRAY['mv_takers_summary'];
    view_name TEXT;
BEGIN
    -- Check regular views
    FOREACH view_name IN ARRAY required_views LOOP
        IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name = view_name) THEN
            missing_views := array_append(missing_views, view_name);
        END IF;
    END LOOP;
    
    -- Check materialized views
    FOREACH view_name IN ARRAY required_mvs LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_matviews WHERE matviewname = view_name
        ) THEN
            missing_views := array_append(missing_views, view_name || ' (materialized)');
        END IF;
    END LOOP;
    
    IF array_length(missing_views, 1) > 0 THEN
        RAISE EXCEPTION 'View restoration failed: missing views: %', array_to_string(missing_views, ', ');
    END IF;
    
    -- Count views created
    SELECT COUNT(*) INTO view_count 
    FROM information_schema.views 
    WHERE table_name IN ('active_auction_rounds', 'recent_takes', 'vw_takes', 'vw_auctions', 'vw_takes_enriched');
    
    SELECT COUNT(*) INTO mv_count 
    FROM pg_matviews 
    WHERE matviewname = 'mv_takers_summary';
    
    RAISE NOTICE '✅ Database views restoration completed successfully!';
    RAISE NOTICE '   - Regular views created: %', view_count;
    RAISE NOTICE '   - Materialized views created: %', mv_count;
    RAISE NOTICE '   - All views required by API are now available';
    RAISE NOTICE '   - Performance indexes created';
    RAISE NOTICE '   - Helper functions added';
END $$;

COMMIT;