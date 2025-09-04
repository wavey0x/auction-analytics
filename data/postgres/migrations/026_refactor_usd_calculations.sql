-- Migration 026: Refactor USD calculations to use views instead of stored columns
-- This migration removes redundant USD columns from takes table and creates
-- comprehensive views for dynamic USD calculations

BEGIN;

-- Drop existing vw_takers_summary materialized view first (it depends on USD columns)
DROP MATERIALIZED VIEW IF EXISTS vw_takers_summary CASCADE;

-- Drop existing redundant indexes first
DROP INDEX IF EXISTS idx_takes_taker_volume;

-- Remove redundant USD columns that are all NULL anyway (safe on takes table)
ALTER TABLE takes DROP COLUMN IF EXISTS amount_taken_usd CASCADE;
ALTER TABLE takes DROP COLUMN IF EXISTS amount_paid_usd CASCADE;
ALTER TABLE takes DROP COLUMN IF EXISTS from_token_price_usd CASCADE;
ALTER TABLE takes DROP COLUMN IF EXISTS to_token_price_usd CASCADE;

-- Create enhanced takes view with improved price matching logic
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
        
        RAISE NOTICE '✅ Created enhanced view with token_prices integration';
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
        
        RAISE NOTICE '⚠️ Created simplified view without USD calculations (token_prices table missing)';
    END IF;
END $$;

-- Create basic materialized view for taker analytics (works with or without USD data)
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

-- Create performance indexes
CREATE UNIQUE INDEX idx_mv_takers_summary_taker ON mv_takers_summary(taker);
CREATE INDEX idx_mv_takers_summary_volume ON mv_takers_summary(total_volume_usd DESC NULLS LAST);
CREATE INDEX idx_mv_takers_summary_takes ON mv_takers_summary(total_takes DESC);

-- Create function to refresh materialized views
CREATE OR REPLACE FUNCTION refresh_taker_analytics()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_takers_summary;
    RAISE NOTICE 'Refreshed mv_takers_summary materialized view';
END;
$$ LANGUAGE plpgsql;

-- Add helpful comments
COMMENT ON VIEW vw_takes_enriched IS 'Enhanced takes view with dynamic USD calculations (if available), token/round context';
COMMENT ON MATERIALIZED VIEW mv_takers_summary IS 'Pre-calculated taker statistics with rankings and activity metrics';

-- Verification
DO $$
DECLARE
    takes_count INTEGER;
    takers_count INTEGER;
    mv_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO takes_count FROM takes;
    SELECT COUNT(DISTINCT taker) INTO takers_count FROM takes WHERE taker IS NOT NULL;
    SELECT COUNT(*) INTO mv_count FROM mv_takers_summary;
    
    RAISE NOTICE '✅ Migration 026 completed successfully:';
    RAISE NOTICE '  - Total takes: %', takes_count;
    RAISE NOTICE '  - Unique takers: %', takers_count;
    RAISE NOTICE '  - Takers in summary: %', mv_count;
    RAISE NOTICE '  - Removed NULL USD columns from takes table';
    RAISE NOTICE '  - Created vw_takes_enriched view';
    RAISE NOTICE '  - Created mv_takers_summary materialized view';
END $$;

COMMIT;