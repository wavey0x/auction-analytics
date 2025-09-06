-- Create takers summary materialized view and performance indexes
-- Idempotent: drops existing MV, recreates it, and ensures indexes exist

BEGIN;

-- Drop existing MV if present (safe re-create)
DROP MATERIALIZED VIEW IF EXISTS public.mv_takers_summary CASCADE;

-- Materialized view aggregating taker statistics from enriched takes
CREATE MATERIALIZED VIEW public.mv_takers_summary AS
WITH taker_base_stats AS (
    SELECT 
        LOWER(t.taker) AS taker,
        COUNT(*) AS total_takes,
        COUNT(DISTINCT t.auction_address) AS unique_auctions,
        COUNT(DISTINCT t.chain_id) AS unique_chains,
        COALESCE(SUM(t.amount_taken_usd), 0) AS total_volume_usd,
        AVG(t.amount_taken_usd) AS avg_take_size_usd,
        COALESCE(SUM(t.price_differential_usd), 0) AS total_profit_usd,
        AVG(t.price_differential_usd) AS avg_profit_per_take_usd,
        MIN(t.timestamp) AS first_take,
        MAX(t.timestamp) AS last_take,
        ARRAY_AGG(DISTINCT t.chain_id ORDER BY t.chain_id) AS active_chains,
        -- Recent activity metrics
        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days') AS takes_last_7d,
        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days') AS takes_last_30d,
        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days'), 0) AS volume_last_7d,
        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days'), 0) AS volume_last_30d,
        COUNT(*) FILTER (WHERE t.price_differential_usd > 0) AS profitable_takes,
        COUNT(*) FILTER (WHERE t.price_differential_usd < 0) AS unprofitable_takes
    FROM public.vw_takes_enriched t
    WHERE t.taker IS NOT NULL
    GROUP BY LOWER(t.taker)
)
SELECT 
    *,
    -- Rankings
    RANK() OVER (ORDER BY total_takes DESC) AS rank_by_takes,
    RANK() OVER (ORDER BY total_volume_usd DESC NULLS LAST) AS rank_by_volume,
    RANK() OVER (ORDER BY total_profit_usd DESC NULLS LAST) AS rank_by_profit,
    -- Success rate calculation
    CASE 
        WHEN (profitable_takes + unprofitable_takes) > 0 
        THEN profitable_takes::DECIMAL / (profitable_takes + unprofitable_takes) * 100
        ELSE NULL
    END AS success_rate_percent
FROM taker_base_stats;

-- Performance indexes for common sorts and filters
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_takers_summary_taker ON public.mv_takers_summary(taker);
CREATE INDEX IF NOT EXISTS idx_mv_takers_summary_volume ON public.mv_takers_summary(total_volume_usd DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_mv_takers_summary_takes ON public.mv_takers_summary(total_takes DESC);
CREATE INDEX IF NOT EXISTS idx_mv_takers_summary_last_take ON public.mv_takers_summary(last_take DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_mv_takers_summary_active_chains_gin ON public.mv_takers_summary USING GIN (active_chains);

-- Helper: safe refresh function (CONCURRENTLY when possible)
CREATE OR REPLACE FUNCTION public.refresh_mv_takers_summary() RETURNS void AS $$
BEGIN
    BEGIN
        EXECUTE 'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_takers_summary';
    EXCEPTION WHEN feature_not_supported THEN
        EXECUTE 'REFRESH MATERIALIZED VIEW mv_takers_summary';
    END;
END;
$$ LANGUAGE plpgsql;

COMMENT ON MATERIALIZED VIEW public.mv_takers_summary IS 'Pre-calculated taker statistics with rankings and activity metrics';

COMMIT;

