-- Complete fix for duplicate take_seq entries
-- Regenerate ALL sequences for affected rounds to ensure no conflicts

\echo 'Starting complete duplicate take_seq fix...'

-- Step 1: Identify all rounds that have (or had) duplicates
CREATE TEMP TABLE affected_rounds AS
SELECT DISTINCT auction_address, chain_id, round_id
FROM takes
WHERE (auction_address, chain_id, round_id, take_seq) IN (
    SELECT auction_address, chain_id, round_id, take_seq
    FROM takes
    GROUP BY auction_address, chain_id, round_id, take_seq
    HAVING COUNT(*) > 1
) OR (auction_address, chain_id, round_id) IN (
    SELECT auction_address, chain_id, round_id
    FROM takes_backup_before_seq_fix
);

\echo 'Found affected rounds, regenerating all sequences...'

-- Step 2: Create complete sequence reassignment for ALL takes in affected rounds
CREATE TEMP TABLE complete_sequences AS
WITH ranked_takes AS (
    SELECT 
        take_id,
        auction_address,
        chain_id,
        round_id,
        take_seq as old_seq,
        block_number,
        log_index,
        transaction_hash,
        -- Assign completely new sequences based on chronological order
        ROW_NUMBER() OVER (
            PARTITION BY auction_address, chain_id, round_id 
            ORDER BY block_number ASC, log_index ASC, transaction_hash ASC
        ) as new_seq
    FROM takes
    WHERE (auction_address, chain_id, round_id) IN (
        SELECT auction_address, chain_id, round_id FROM affected_rounds
    )
)
SELECT 
    take_id,
    auction_address,
    chain_id,
    round_id,
    old_seq,
    new_seq,
    auction_address || '-' || round_id || '-' || new_seq as new_take_id
FROM ranked_takes;

-- Step 3: Update ALL takes in affected rounds with new sequences
\echo 'Updating all take sequences in affected rounds...'

UPDATE takes 
SET 
    take_seq = cs.new_seq,
    take_id = cs.new_take_id
FROM complete_sequences cs
WHERE takes.take_id = cs.take_id;

-- Step 4: Final verification
\echo 'Final verification - checking for remaining duplicates:'
SELECT 
    COUNT(*) as remaining_duplicates
FROM (
    SELECT auction_address, chain_id, round_id, take_seq
    FROM takes
    GROUP BY auction_address, chain_id, round_id, take_seq
    HAVING COUNT(*) > 1
) duplicates;

\echo 'Final verification - checking for duplicate take_ids:'
SELECT 
    COUNT(*) as duplicate_take_ids
FROM (
    SELECT take_id
    FROM takes
    GROUP BY take_id
    HAVING COUNT(*) > 1
) dup_ids;

-- Step 5: Show sample of fixed data  
\echo 'Sample of completely fixed rounds:'
SELECT 
    auction_address,
    chain_id,
    round_id,
    take_seq,
    take_id,
    block_number,
    LEFT(transaction_hash, 10) || '...' as tx_hash_short
FROM takes
WHERE (auction_address, chain_id, round_id) IN (
    SELECT auction_address, chain_id, round_id
    FROM affected_rounds
    LIMIT 3
)
ORDER BY auction_address, chain_id, round_id, take_seq;

\echo 'Complete duplicate take_seq fix finished successfully!'