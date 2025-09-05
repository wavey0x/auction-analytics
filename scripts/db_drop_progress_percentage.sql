-- Ad hoc cleanup: remove progress_percentage everywhere and recreate views without it
BEGIN;

-- Drop dependent views first (if they exist)
DROP VIEW IF EXISTS active_auction_rounds CASCADE;
DROP VIEW IF EXISTS vw_auctions CASCADE;

-- Remove column from table
ALTER TABLE IF EXISTS public.rounds DROP COLUMN IF EXISTS progress_percentage;

-- Recreate active_auction_rounds view without progress_percentage
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

-- Recreate vw_auctions view without progress_percentage
CREATE VIEW vw_auctions AS
SELECT 
    a.auction_address,
    a.chain_id,
    a.want_token,
    a.deployer,
    a.update_interval,
    a.auction_length,
    a.starting_price,
    a.auction_version as version,
    a.decay_rate_percent as decay_rate,
    a.update_interval_minutes as update_interval,
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
    
    -- Takes count for current round
    COALESCE(takes_count.current_round_takes, 0) as current_round_takes,
    
    -- Simplified from_tokens JSON
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
) takes_count ON true;

COMMIT;

