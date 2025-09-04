-- Migration 039: Unified migration to standardize views and constraints
-- - Drops obsolete MV and replaces with dynamic vw_takers_summary
-- - Fixes active_auction_rounds to use epoch seconds and token metadata
-- - Fixes vw_auctions to expose epoch timing and enabled token metadata
-- - Adds unique constraint for price_requests (chain_id, block_number, token_address)
-- - Makes auctions.step_decay nullable when necessary
-- Idempotent and safe to run multiple times.

BEGIN;

-- 0) Harden preconditions: schema exists
SET search_path TO public, pg_catalog;

-- 1) Make auctions.step_decay nullable (if currently NOT NULL)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='auctions' AND column_name='step_decay' AND is_nullable='NO'
  ) THEN
    EXECUTE 'ALTER TABLE public.auctions ALTER COLUMN step_decay DROP NOT NULL';
  END IF;
END $$;

-- 2) Add unique constraint to price_requests on (chain_id, block_number, token_address)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='price_requests') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.table_constraints 
      WHERE table_schema='public' AND table_name='price_requests' AND constraint_name='price_requests_chain_block_token_unique'
    ) THEN
      -- Ensure no duplicates exist before enabling this constraint in production.
      EXECUTE 'ALTER TABLE public.price_requests 
               ADD CONSTRAINT price_requests_chain_block_token_unique 
               UNIQUE (chain_id, block_number, token_address)';
    END IF;
  END IF;
END $$;

-- 3) Replace materialized takers summary with dynamic view
DROP MATERIALIZED VIEW IF EXISTS public.mv_takers_summary CASCADE;

CREATE OR REPLACE VIEW public.vw_takers_summary AS
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
    FROM public.vw_takes_enriched t
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

-- No-op refresh helpers so old jobs don’t fail
CREATE OR REPLACE FUNCTION public.refresh_taker_analytics() RETURNS void AS $$
BEGIN
    RAISE NOTICE 'vw_takers_summary is a regular view; no refresh needed.';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.refresh_takers_summary() RETURNS void AS $$
BEGIN
    RAISE NOTICE 'vw_takers_summary is a regular view; no refresh needed.';
END;
$$ LANGUAGE plpgsql;

-- 4) Fix active rounds view to use epoch arithmetic and include token metadata
DROP VIEW IF EXISTS public.active_auction_rounds CASCADE;

CREATE VIEW public.active_auction_rounds AS
SELECT 
    r.auction_address,
    r.chain_id,
    r.round_id,
    r.from_token,
    r.kicked_at,                            -- bigint epoch
    r.initial_available,
    r.available_amount,
    r.total_volume_sold,
    r.progress_percentage,
    r.block_number,
    r.transaction_hash,
    (r.round_end IS NOT NULL AND r.round_end > EXTRACT(EPOCH FROM NOW())::BIGINT AND COALESCE(r.available_amount, 0) > 0) AS is_active,
    GREATEST(0, (r.round_end - EXTRACT(EPOCH FROM NOW())::BIGINT))::INTEGER AS time_remaining,
    GREATEST(0, (EXTRACT(EPOCH FROM NOW())::BIGINT - COALESCE(r.round_start, r.kicked_at)))::INTEGER AS seconds_elapsed,
    NULL::NUMERIC AS current_price,         -- placeholder until price calc is implemented
    a.want_token,
    a.decay_rate,
    a.update_interval,
    a.auction_length,
    a.step_decay_rate,
    tf.symbol AS from_token_symbol,
    tf.name   AS from_token_name,
    tf.decimals AS from_token_decimals
FROM public.rounds r
JOIN public.auctions a
  ON LOWER(r.auction_address) = LOWER(a.auction_address)
 AND r.chain_id = a.chain_id
LEFT JOIN public.tokens tf
  ON LOWER(tf.address) = LOWER(r.from_token)
 AND tf.chain_id = r.chain_id
WHERE (r.round_end IS NULL OR r.round_end > EXTRACT(EPOCH FROM NOW())::BIGINT)
  AND COALESCE(r.available_amount, 0) > 0
ORDER BY r.kicked_at DESC;

COMMENT ON VIEW public.active_auction_rounds IS 'Active rounds with epoch-based timing and from_token metadata';

-- 5) Fix vw_auctions to expose epoch timing and enabled token metadata
DROP VIEW IF EXISTS public.vw_auctions CASCADE;

CREATE VIEW public.vw_auctions AS
SELECT 
    a.auction_address,
    a.chain_id,
    a.want_token,
    a.deployer,
    a.update_interval AS price_update_interval,
    a.auction_length,
    a.starting_price,
    wt.symbol  AS want_token_symbol,
    wt.name    AS want_token_name,
    wt.decimals AS want_token_decimals,
    cr.round_id           AS current_round_id,
    cr.is_active          AS has_active_round,
    cr.available_amount   AS current_available,
    cr.kicked_at          AS last_kicked,
    COALESCE(cr.round_start, cr.kicked_at) AS round_start,
    cr.round_end          AS round_end,
    CASE 
        WHEN cr.initial_available > 0 AND cr.available_amount IS NOT NULL 
        THEN ROUND((1.0 - (cr.available_amount::DECIMAL / cr.initial_available::DECIMAL)) * 100, 2)
        ELSE 0.0 
    END AS progress_percentage,
    COALESCE(takes_count.current_round_takes, 0) AS current_round_takes,
    cr.from_token AS current_round_from_token,
    cr.transaction_hash AS current_round_transaction_hash,
    ft.from_tokens_json
FROM public.auctions a
LEFT JOIN public.tokens wt
  ON LOWER(a.want_token) = LOWER(wt.address)
 AND a.chain_id = wt.chain_id
LEFT JOIN LATERAL (
    SELECT 
        r.round_id,
        r.kicked_at,
        r.round_start,
        r.round_end,
        r.initial_available,
        r.available_amount,
        (r.round_end IS NOT NULL AND r.round_end > EXTRACT(EPOCH FROM NOW())::BIGINT AND COALESCE(r.available_amount,0) > 0) AS is_active,
        r.from_token,
        r.transaction_hash
    FROM public.rounds r
    WHERE LOWER(r.auction_address) = LOWER(a.auction_address)
      AND r.chain_id = a.chain_id
    ORDER BY r.round_id DESC
    LIMIT 1
) cr ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS current_round_takes
    FROM public.takes t
    WHERE LOWER(t.auction_address) = LOWER(a.auction_address)
      AND t.chain_id = a.chain_id
      AND t.round_id = cr.round_id
) takes_count ON TRUE
LEFT JOIN LATERAL (
    SELECT COALESCE(
      json_agg(
        json_build_object(
          'address', et.token_address,
          'symbol', COALESCE(tk.symbol, 'Unknown'),
          'name', COALESCE(tk.name, 'Unknown'),
          'decimals', COALESCE(tk.decimals, 18),
          'chain_id', et.chain_id
        ) ORDER BY et.enabled_at
      ), '[]'::json
    ) AS from_tokens_json
    FROM public.enabled_tokens et
    LEFT JOIN public.tokens tk
      ON LOWER(tk.address) = LOWER(et.token_address)
     AND tk.chain_id = et.chain_id
    WHERE LOWER(et.auction_address) = LOWER(a.auction_address)
      AND et.chain_id = a.chain_id
) ft ON TRUE;

COMMENT ON VIEW public.vw_auctions IS 'Comprehensive auction view with epoch-based timing and enabled token metadata';

COMMIT;
