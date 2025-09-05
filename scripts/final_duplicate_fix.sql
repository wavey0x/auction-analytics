-- Final comprehensive fix for duplicate take sequences
-- Delete and re-insert all takes from affected rounds with proper sequences

\echo 'Starting final duplicate fix...'

-- Step 1: Create backup and identify affected rounds
CREATE TEMP TABLE final_backup AS
SELECT * FROM takes
WHERE (auction_address, chain_id, round_id) IN (
    SELECT DISTINCT auction_address, chain_id, round_id
    FROM takes
    WHERE (auction_address, chain_id, round_id, take_seq) IN (
        SELECT auction_address, chain_id, round_id, take_seq
        FROM takes
        GROUP BY auction_address, chain_id, round_id, take_seq
        HAVING COUNT(*) > 1
    )
);

\echo 'Created backup of affected takes'

-- Step 2: Create properly sequenced version
CREATE TEMP TABLE properly_sequenced AS
WITH sequenced AS (
    SELECT 
        t.*,
        ROW_NUMBER() OVER (
            PARTITION BY t.auction_address, t.chain_id, t.round_id 
            ORDER BY t.block_number ASC, t.log_index ASC, t.transaction_hash ASC
        ) as new_seq
    FROM final_backup t
)
SELECT 
    s.*,
    s.auction_address || '-' || s.round_id || '-' || s.new_seq as new_take_id
FROM sequenced s;

\echo 'Generated proper sequences'

-- Step 3: Delete the duplicated takes
DELETE FROM takes
WHERE (auction_address, chain_id, round_id) IN (
    SELECT DISTINCT auction_address, chain_id, round_id FROM final_backup
);

-- Step 4: Insert properly sequenced takes
INSERT INTO takes (
    take_id, auction_address, chain_id, round_id, take_seq,
    taker, from_token, to_token, amount_taken, amount_paid, price,
    timestamp, seconds_from_round_start,
    block_number, transaction_hash, log_index,
    gas_price, base_fee, priority_fee, gas_used, transaction_fee_eth
)
SELECT 
    new_take_id, auction_address, chain_id, round_id, new_seq,
    taker, from_token, to_token, amount_taken, amount_paid, price,
    timestamp, seconds_from_round_start,
    block_number, transaction_hash, log_index,
    gas_price, base_fee, priority_fee, gas_used, transaction_fee_eth
FROM properly_sequenced
ORDER BY auction_address, chain_id, round_id, new_seq;

\echo 'Re-inserted properly sequenced takes'

-- Verification
SELECT 'Final verification - remaining duplicates:', COUNT(*)
FROM (
    SELECT auction_address, chain_id, round_id, take_seq
    FROM takes
    GROUP BY auction_address, chain_id, round_id, take_seq
    HAVING COUNT(*) > 1
) duplicates;

SELECT 'Final verification - duplicate take_ids:', COUNT(*)
FROM (
    SELECT take_id FROM takes GROUP BY take_id HAVING COUNT(*) > 1
) dup_ids;

\echo 'Final duplicate fix completed!'