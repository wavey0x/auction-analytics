-- Migration 036: Fix vw_takes_enriched view returning duplicate takes
-- 
-- ROOT CAUSE: Multiple token_prices records for the same token at the same block
-- cause the LEFT JOINs with token_prices to multiply rows, creating duplicates.
--
-- SOLUTION: 
-- 1. Use DISTINCT ON to get the latest price record per token/block
-- 2. Remove excessive text casting and parentheses for cleaner code
-- 3. Backup original view definition first
--
-- BACKUP: Original view backed up to /tmp/vw_takes_enriched_backup.sql

BEGIN;

-- Create backup of original view in comments for rollback reference
/*
ORIGINAL VIEW DEFINITION (backed up):
CREATE VIEW vw_takes_enriched AS  SELECT t.take_id,
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
    t."timestamp",
    t.seconds_from_round_start,
    t.block_number,
    t.transaction_hash,
    t.log_index,
    t.gas_price,
    t.base_fee,
    t.priority_fee,
    t.gas_used,
    t.transaction_fee_eth,
    to_timestamp((r.kicked_at)::double precision) AS round_kicked_at,
    r.initial_available AS round_initial_available,
    a.want_token,
    tf.symbol AS from_token_symbol,
    tf.name AS from_token_name,
    tf.decimals AS from_token_decimals,
    tt.symbol AS to_token_symbol,
    tt.name AS to_token_name,
    tt.decimals AS to_token_decimals,
    wt.symbol AS want_token_symbol,
    wt.name AS want_token_name,
    wt.decimals AS want_token_decimals,
    fprice.price_usd AS from_token_price_usd,
    tprice.price_usd AS to_token_price_usd,
    (t.amount_taken * COALESCE(fprice.price_usd, (0)::numeric)) AS amount_taken_usd,
    (t.amount_paid * COALESCE(tprice.price_usd, (0)::numeric)) AS amount_paid_usd,
    ((t.amount_taken * COALESCE(fprice.price_usd, (0)::numeric)) - (t.amount_paid * COALESCE(tprice.price_usd, (0)::numeric))) AS price_differential_usd,
        CASE
            WHEN ((t.amount_paid * COALESCE(tprice.price_usd, (0)::numeric)) > (0)::numeric) THEN ((((t.amount_taken * COALESCE(fprice.price_usd, (0)::numeric)) - (t.amount_paid * COALESCE(tprice.price_usd, (0)::numeric))) / (t.amount_paid * COALESCE(tprice.price_usd, (0)::numeric))) * (100)::numeric)
            ELSE NULL::numeric
        END AS price_differential_percent,
    NULL::numeric AS transaction_fee_usd
   FROM (((((((takes t
     LEFT JOIN rounds r ON ((((t.auction_address)::text = (r.auction_address)::text) AND (t.chain_id = r.chain_id) AND (t.round_id = r.round_id))))
     LEFT JOIN auctions a ON ((((t.auction_address)::text = (a.auction_address)::text) AND (t.chain_id = a.chain_id))))
     LEFT JOIN tokens tf ON (((lower((tf.address)::text) = lower((t.from_token)::text)) AND (tf.chain_id = t.chain_id))))
     LEFT JOIN tokens tt ON (((lower((tt.address)::text) = lower((t.to_token)::text)) AND (tt.chain_id = t.chain_id))))
     LEFT JOIN tokens wt ON (((lower((wt.address)::text) = lower((a.want_token)::text)) AND (wt.chain_id = a.chain_id))))
     LEFT JOIN token_prices fprice ON ((((fprice.token_address)::text = (t.from_token)::text) AND (fprice.chain_id = t.chain_id) AND (fprice.block_number = t.block_number))))
     LEFT JOIN token_prices tprice ON ((((tprice.token_address)::text = (t.to_token)::text) AND (tprice.chain_id = t.chain_id) AND (tprice.block_number = t.block_number))));
*/

-- First backup dependent views
CREATE TEMP TABLE temp_vw_takers_summary_backup AS 
SELECT pg_get_viewdef('vw_takers_summary') as view_def;

CREATE TEMP TABLE temp_mv_takers_summary_backup AS 
SELECT pg_get_viewdef('mv_takers_summary') as view_def;

-- Drop dependent objects first
DROP VIEW IF EXISTS vw_takers_summary CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_takers_summary CASCADE;

-- Drop the main view
DROP VIEW IF EXISTS vw_takes_enriched;

-- Recreate the view with fixes:
-- 1. Use DISTINCT ON subqueries for token_prices to prevent duplicates
-- 2. Remove excessive text casting and parentheses 
-- 3. Cleaner, more readable JOIN conditions
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
    to_timestamp(r.kicked_at::double precision) AS round_kicked_at,
    r.initial_available AS round_initial_available,
    a.want_token,
    tf.symbol AS from_token_symbol,
    tf.name AS from_token_name,
    tf.decimals AS from_token_decimals,
    tt.symbol AS to_token_symbol,
    tt.name AS to_token_name,
    tt.decimals AS to_token_decimals,
    wt.symbol AS want_token_symbol,
    wt.name AS want_token_name,
    wt.decimals AS want_token_decimals,
    fprice.price_usd AS from_token_price_usd,
    tprice.price_usd AS to_token_price_usd,
    (t.amount_taken * COALESCE(fprice.price_usd, 0)) AS amount_taken_usd,
    (t.amount_paid * COALESCE(tprice.price_usd, 0)) AS amount_paid_usd,
    ((t.amount_taken * COALESCE(fprice.price_usd, 0)) - (t.amount_paid * COALESCE(tprice.price_usd, 0))) AS price_differential_usd,
    CASE
        WHEN (t.amount_paid * COALESCE(tprice.price_usd, 0)) > 0 
        THEN (((t.amount_taken * COALESCE(fprice.price_usd, 0)) - (t.amount_paid * COALESCE(tprice.price_usd, 0))) / (t.amount_paid * COALESCE(tprice.price_usd, 0))) * 100
        ELSE NULL
    END AS price_differential_percent,
    NULL::numeric AS transaction_fee_usd
FROM takes t
    LEFT JOIN rounds r ON (
        t.auction_address = r.auction_address 
        AND t.chain_id = r.chain_id 
        AND t.round_id = r.round_id
    )
    LEFT JOIN auctions a ON (
        t.auction_address = a.auction_address 
        AND t.chain_id = a.chain_id
    )
    LEFT JOIN tokens tf ON (
        lower(tf.address) = lower(t.from_token) 
        AND tf.chain_id = t.chain_id
    )
    LEFT JOIN tokens tt ON (
        lower(tt.address) = lower(t.to_token) 
        AND tt.chain_id = t.chain_id
    )
    LEFT JOIN tokens wt ON (
        lower(wt.address) = lower(a.want_token) 
        AND wt.chain_id = a.chain_id
    )
    -- Use DISTINCT ON subqueries to get single price record per token/block
    LEFT JOIN (
        SELECT DISTINCT ON (token_address, chain_id, block_number) 
            token_address, chain_id, block_number, price_usd
        FROM token_prices
        ORDER BY token_address, chain_id, block_number, created_at DESC
    ) fprice ON (
        fprice.token_address = t.from_token 
        AND fprice.chain_id = t.chain_id 
        AND fprice.block_number = t.block_number
    )
    LEFT JOIN (
        SELECT DISTINCT ON (token_address, chain_id, block_number) 
            token_address, chain_id, block_number, price_usd
        FROM token_prices
        ORDER BY token_address, chain_id, block_number, created_at DESC
    ) tprice ON (
        tprice.token_address = t.to_token 
        AND tprice.chain_id = t.chain_id 
        AND tprice.block_number = t.block_number
    );

-- Test the fix on the problematic case
DO $$
DECLARE
    duplicate_count integer;
    test_take_id text;
BEGIN
    SELECT COUNT(*), MAX(take_id) INTO duplicate_count, test_take_id
    FROM vw_takes_enriched
    WHERE lower(auction_address) = lower('0x8d56019B30024DE6e22A75fB256442513C861618')
        AND round_id = 70;
    
    IF duplicate_count != 1 THEN
        RAISE EXCEPTION 'View fix failed: expected 1 row, got % rows for test case (take_id: %)', duplicate_count, test_take_id;
    ELSE
        RAISE NOTICE 'View fix successful: test case returns exactly 1 row (take_id: %)', test_take_id;
    END IF;
END $$;

-- Additional validation: Check that total take count remains reasonable
DO $$
DECLARE
    view_count integer;
    table_count integer;
BEGIN
    SELECT COUNT(*) INTO view_count FROM vw_takes_enriched;
    SELECT COUNT(*) INTO table_count FROM takes;
    
    IF view_count > table_count * 1.1 THEN
        RAISE WARNING 'View may still have duplicates: % rows in view vs % rows in base table', view_count, table_count;
    ELSE
        RAISE NOTICE 'View row count looks good: % rows (base table: % rows)', view_count, table_count;
    END IF;
END $$;

-- Recreate dependent views from backup
DO $$
DECLARE
    vw_takers_def text;
    mv_takers_def text;
BEGIN
    -- Get backed up view definitions
    SELECT view_def INTO vw_takers_def FROM temp_vw_takers_summary_backup;
    SELECT view_def INTO mv_takers_def FROM temp_mv_takers_summary_backup;
    
    -- Recreate vw_takers_summary
    EXECUTE 'CREATE VIEW vw_takers_summary AS ' || vw_takers_def;
    RAISE NOTICE 'Recreated vw_takers_summary view';
    
    -- Recreate mv_takers_summary  
    EXECUTE 'CREATE MATERIALIZED VIEW mv_takers_summary AS ' || mv_takers_def;
    RAISE NOTICE 'Recreated mv_takers_summary materialized view';
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Failed to recreate dependent views: %. You may need to recreate them manually.', SQLERRM;
END $$;

COMMIT;