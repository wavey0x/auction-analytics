-- Creates a materialized view for enriched takes with USD prices precomputed.
-- This reduces per-request LATERAL lookups into token_prices.

BEGIN;

DROP MATERIALIZED VIEW IF EXISTS mv_takes_enriched CASCADE;

CREATE MATERIALIZED VIEW mv_takes_enriched AS
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
    -- Price information (closest block <= take block)
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
LEFT JOIN rounds r ON t.auction_address = r.auction_address 
                  AND t.chain_id = r.chain_id 
                  AND t.round_id = r.round_id
LEFT JOIN tokens tf ON LOWER(tf.address) = LOWER(t.from_token) 
                   AND tf.chain_id = t.chain_id
LEFT JOIN tokens tt ON LOWER(tt.address) = LOWER(t.to_token) 
                   AND tt.chain_id = t.chain_id
-- Price for from_token at/before block
LEFT JOIN LATERAL (
    SELECT price_usd 
    FROM token_prices 
    WHERE chain_id = t.chain_id 
      AND LOWER(token_address) = LOWER(t.from_token)
      AND block_number <= t.block_number
    ORDER BY block_number DESC, created_at DESC
    LIMIT 1
) tp_from ON true
-- Price for to_token (want) at/before block
LEFT JOIN LATERAL (
    SELECT price_usd 
    FROM token_prices 
    WHERE chain_id = t.chain_id 
      AND LOWER(token_address) = LOWER(t.to_token)
      AND block_number <= t.block_number
    ORDER BY block_number DESC, created_at DESC
    LIMIT 1
) tp_to ON true
-- ETH price for gas cost
LEFT JOIN LATERAL (
    SELECT price_usd
    FROM token_prices tp_eth
    WHERE tp_eth.chain_id = t.chain_id 
      AND (
        LOWER(tp_eth.token_address) LIKE '%eth%' OR 
        LOWER(tp_eth.token_address) = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
      )
      AND tp_eth.block_number <= t.block_number
    ORDER BY tp_eth.block_number DESC
    LIMIT 1
) tp_eth ON true;

-- Unique index required for CONCURRENT refresh
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_takes_enriched_take_id
  ON mv_takes_enriched(take_id);

-- Helpful read indexes for common access patterns
CREATE INDEX IF NOT EXISTS idx_mv_takes_enriched_taker_ts
  ON mv_takes_enriched (LOWER(taker), timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_mv_takes_enriched_auction_chain_ts
  ON mv_takes_enriched (LOWER(auction_address), chain_id, timestamp DESC);

COMMIT;

