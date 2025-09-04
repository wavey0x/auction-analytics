-- Creates a dynamic view for taker summaries computed from vw_takes_enriched.
-- Use when the materialized view is missing or stale.

CREATE OR REPLACE VIEW vw_takers_summary AS
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
        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days') AS takes_last_7d,
        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days') AS takes_last_30d,
        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days'), 0) AS volume_last_7d,
        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days'), 0) AS volume_last_30d,
        COUNT(*) FILTER (WHERE t.price_differential_usd > 0) AS profitable_takes,
        COUNT(*) FILTER (WHERE t.price_differential_usd < 0) AS unprofitable_takes
    FROM vw_takes_enriched t
    WHERE t.taker IS NOT NULL
    GROUP BY LOWER(t.taker)
)
SELECT 
    *,
    RANK() OVER (ORDER BY total_takes DESC) AS rank_by_takes,
    RANK() OVER (ORDER BY total_volume_usd DESC NULLS LAST) AS rank_by_volume,
    RANK() OVER (ORDER BY total_profit_usd DESC NULLS LAST) AS rank_by_profit,
    CASE 
        WHEN (profitable_takes + unprofitable_takes) > 0
        THEN profitable_takes::DECIMAL / (profitable_takes + unprofitable_takes) * 100
        ELSE NULL
    END AS success_rate_percent
FROM taker_base_stats;

-- Optional: Keep a compatibility shim so any code expecting mv_ keeps working
-- CREATE MATERIALIZED VIEW IF NOT EXISTS mv_takers_summary AS
-- SELECT * FROM vw_takers_summary;
-- CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_takers_summary_taker ON mv_takers_summary(taker);
