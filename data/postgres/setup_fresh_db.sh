#!/bin/bash

set -e

# Get database URL from environment or parameter
DB_URL=${1:-$DATABASE_URL}

if [ -z "$DB_URL" ]; then
    echo "Error: DATABASE_URL not set and no URL provided"
    echo "Usage: $0 [database_url]"
    exit 1
fi

echo "Setting up fresh database at: $DB_URL"

# 1. Drop and recreate schema (wipes everything clean)
echo "Dropping existing schema..."
psql "$DB_URL" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

# 2. Load the base schema
echo "Loading base schema..."
psql "$DB_URL" < data/postgres/schema.sql

# 3. Fix all missing sequences and constraints
echo "Fixing sequences and constraints..."
psql "$DB_URL" << 'SQL'
-- Fix indexer_state table
CREATE SEQUENCE IF NOT EXISTS indexer_state_id_seq;
ALTER TABLE indexer_state ALTER COLUMN id SET DEFAULT nextval('indexer_state_id_seq');
ALTER SEQUENCE indexer_state_id_seq OWNED BY indexer_state.id;
SELECT setval('indexer_state_id_seq', COALESCE(MAX(id), 0) + 1) FROM indexer_state;

-- Fix tokens table  
DROP SEQUENCE IF EXISTS tokens_id_seq CASCADE;
CREATE SEQUENCE tokens_id_seq;
ALTER TABLE tokens ALTER COLUMN id SET DEFAULT nextval('tokens_id_seq');
ALTER SEQUENCE tokens_id_seq OWNED BY tokens.id;
SELECT setval('tokens_id_seq', COALESCE(MAX(id), 0) + 1) FROM tokens;

-- Fix rounds table
CREATE SEQUENCE IF NOT EXISTS rounds_id_seq;
ALTER TABLE rounds ALTER COLUMN id SET DEFAULT nextval('rounds_id_seq');  
ALTER SEQUENCE rounds_id_seq OWNED BY rounds.id;
SELECT setval('rounds_id_seq', COALESCE(MAX(id), 0) + 1) FROM rounds;

-- Fix takes table
CREATE SEQUENCE IF NOT EXISTS takes_id_seq;
ALTER TABLE takes ALTER COLUMN id SET DEFAULT nextval('takes_id_seq');
ALTER SEQUENCE takes_id_seq OWNED by takes.id; 
SELECT setval('takes_id_seq', COALESCE(MAX(id), 0) + 1) FROM takes;

-- Fix auctions table constraints (make fields nullable to match indexer behavior)
ALTER TABLE auctions ALTER COLUMN step_decay DROP NOT NULL;
ALTER TABLE auctions ALTER COLUMN starting_price DROP NOT NULL; 
ALTER TABLE auctions ALTER COLUMN version DROP NOT NULL;
ALTER TABLE auctions ALTER COLUMN decay_rate DROP NOT NULL;

-- Add missing columns to tokens table
ALTER TABLE tokens ADD COLUMN IF NOT EXISTS first_seen TIMESTAMP WITH TIME ZONE;
ALTER TABLE tokens ADD COLUMN IF NOT EXISTS timestamp TIMESTAMP WITH TIME ZONE;

-- Create missing tables for indexer
CREATE TABLE IF NOT EXISTS outbox_events (
    id SERIAL PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL,
    type VARCHAR(100),
    chain_id INTEGER,
    block_number BIGINT,
    tx_hash VARCHAR(100),
    log_index INTEGER,
    payload JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    processed BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS price_requests (
    id SERIAL PRIMARY KEY,
    token_address VARCHAR(100) NOT NULL,
    chain_id INTEGER NOT NULL,
    block_number BIGINT,
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    processed BOOLEAN DEFAULT FALSE,
    priority INTEGER DEFAULT 1
);
SQL

# 4. Verify setup
echo "Verifying database setup..."
psql "$DB_URL" -c "\dt" 
psql "$DB_URL" -c "\ds"

echo "Database setup complete!"