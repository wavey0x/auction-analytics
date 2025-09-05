-- Fix duplicate take_seq entries by reassigning correct sequences
-- This script addresses the issue where multiple takes in the same round have identical take_seq values

\echo 'Starting duplicate take_seq fix...'

-- Step 1: Create a backup table for safety
CREATE TABLE IF NOT EXISTS takes_backup_before_seq_fix AS 
SELECT * FROM takes LIMIT 0; -- Empty table with same structure

-- Delete any existing backup and create fresh one
DELETE FROM takes_backup_before_seq_fix;
INSERT INTO takes_backup_before_seq_fix SELECT * FROM takes 
WHERE (auction_address, chain_id, round_id, take_seq) IN (
    SELECT auction_address, chain_id, round_id, take_seq
    FROM takes
    GROUP BY auction_address, chain_id, round_id, take_seq
    HAVING COUNT(*) > 1
);

\echo 'Backup created for affected takes.'

-- Step 2: Create a temp table to calculate correct sequences
CREATE TEMP TABLE correct_sequences AS
WITH ranked_takes AS (
    SELECT 
        take_id,
        auction_address,
        chain_id,
        round_id,
        take_seq as old_seq,
        block_number,
        timestamp,
        transaction_hash,
        log_index,
        -- Assign new sequence based on chronological order (block_number, then log_index)
        ROW_NUMBER() OVER (
            PARTITION BY auction_address, chain_id, round_id 
            ORDER BY block_number ASC, log_index ASC
        ) as new_seq
    FROM takes
    WHERE (auction_address, chain_id, round_id, take_seq) IN (
        SELECT auction_address, chain_id, round_id, take_seq
        FROM takes
        GROUP BY auction_address, chain_id, round_id, take_seq
        HAVING COUNT(*) > 1
    )
)
SELECT 
    take_id,
    auction_address,
    chain_id,
    round_id,
    old_seq,
    new_seq,
    block_number,
    timestamp,
    transaction_hash
FROM ranked_takes
WHERE old_seq != new_seq; -- Only include takes that need sequence updates

\echo 'Calculated correct sequences for all duplicate takes.'

-- Step 3: Show what will be updated
\echo 'Preview of changes:'
SELECT 
    auction_address,
    chain_id, 
    round_id,
    COUNT(*) as takes_to_update,
    STRING_AGG(CONCAT('seq ', old_seq, '→', new_seq), ', ' ORDER BY new_seq) as changes
FROM correct_sequences
GROUP BY auction_address, chain_id, round_id
ORDER BY round_id DESC;

-- Step 4: Update take_seq values and take_id values
\echo 'Updating take sequences...'

UPDATE takes 
SET 
    take_seq = cs.new_seq,
    take_id = cs.auction_address || '-' || cs.round_id || '-' || cs.new_seq
FROM correct_sequences cs
WHERE takes.take_id = cs.take_id;

-- Step 5: Verify the fix
\echo 'Verification - checking for remaining duplicates:'
SELECT 
    COUNT(*) as remaining_duplicates
FROM (
    SELECT auction_address, chain_id, round_id, take_seq
    FROM takes
    GROUP BY auction_address, chain_id, round_id, take_seq
    HAVING COUNT(*) > 1
) duplicates;

-- Step 6: Show sample of fixed data
\echo 'Sample of fixed rounds:'
SELECT 
    auction_address,
    chain_id,
    round_id,
    take_seq,
    taker,
    block_number,
    transaction_hash
FROM takes
WHERE (auction_address, chain_id, round_id) IN (
    SELECT DISTINCT auction_address, chain_id, round_id
    FROM correct_sequences
    LIMIT 3
)
ORDER BY auction_address, chain_id, round_id, take_seq;

\echo 'Duplicate take_seq fix completed successfully!'