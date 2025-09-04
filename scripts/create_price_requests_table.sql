-- Create price_requests table to match production structure
-- This table is missing from dev database and needs to be recreated

BEGIN;

-- Create sequence for price_requests
CREATE SEQUENCE IF NOT EXISTS price_requests_id_seq;

-- Create the price_requests table
CREATE TABLE IF NOT EXISTS price_requests (
    id integer NOT NULL DEFAULT nextval('price_requests_id_seq'::regclass),
    chain_id integer NOT NULL,
    block_number bigint NOT NULL,
    token_address character varying(100) NOT NULL,
    request_type character varying(20) NOT NULL,
    auction_address character varying(100),
    round_id integer,
    status character varying(20) DEFAULT 'pending'::character varying,
    created_at timestamp without time zone DEFAULT now(),
    processed_at timestamp without time zone,
    error_message text,
    retry_count integer DEFAULT 0
);

-- Set sequence ownership
ALTER SEQUENCE price_requests_id_seq OWNED BY price_requests.id;

-- Create primary key
ALTER TABLE ONLY price_requests ADD CONSTRAINT price_requests_pkey PRIMARY KEY (id);

-- Create unique constraint (this is the one mentioned by the user)
ALTER TABLE ONLY price_requests ADD CONSTRAINT price_requests_chain_id_block_number_token_address_key UNIQUE (chain_id, block_number, token_address);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_price_requests_chain_token ON price_requests USING btree (chain_id, token_address);
CREATE INDEX IF NOT EXISTS idx_price_requests_created ON price_requests USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_price_requests_status ON price_requests USING btree (status);

-- Add check constraint
ALTER TABLE price_requests ADD CONSTRAINT price_requests_status_check CHECK (status IS NOT NULL AND length(status::text) > 0);

-- Add comments
COMMENT ON TABLE price_requests IS 'Price request tracking table for auction system';
COMMENT ON COLUMN price_requests.request_type IS 'Type of price request (e.g., token_price, market_data)';
COMMENT ON COLUMN price_requests.status IS 'Request status: pending, completed, failed';

-- Verification
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'price_requests') THEN
        RAISE NOTICE '✅ price_requests table created successfully';
    ELSE
        RAISE EXCEPTION 'Failed to create price_requests table';
    END IF;
END $$;

COMMIT;