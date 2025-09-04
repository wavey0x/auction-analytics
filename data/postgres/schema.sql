--
-- PostgreSQL database dump
--

-- Dumped from database version 16.9 (Ubuntu 16.9-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.8 (Debian 16.8-1.pgdg120+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS '';


--
-- Name: check_round_expiry(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_round_expiry() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE rounds ar
    SET is_active = FALSE,
        time_remaining = 0
    FROM auctions ahp
    WHERE ar.auction_address = ahp.auction_address
        AND ar.chain_id = ahp.chain_id
        AND ar.is_active = TRUE
        AND ar.kicked_at + (ahp.auction_length || ' seconds')::INTERVAL < NOW();
END;
$$;


--
-- Name: refresh_taker_analytics(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_taker_analytics() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_takers_summary;
    RAISE NOTICE 'Refreshed mv_takers_summary materialized view';
END;
$$;


--
-- Name: refresh_takers_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_takers_summary() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY vw_takers_summary;
END;
$$;


--
-- Name: update_round_statistics(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_round_statistics() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Update the round statistics when a take is inserted
    UPDATE rounds SET
        total_takes = total_takes + 1,
        available_amount = GREATEST(available_amount - NEW.amount_taken, 0)
    WHERE auction_address = NEW.auction_address
      AND chain_id = NEW.chain_id
      AND round_id = NEW.round_id;
    
    RETURN NEW;
END;
$$;


SET default_table_access_method = heap;

--
-- Name: auctions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auctions (
    auction_address character varying(100) NOT NULL,
    chain_id integer DEFAULT 1 NOT NULL,
    update_interval integer NOT NULL,
    step_decay numeric(30,0) NOT NULL,
    step_decay_rate numeric(30,0),
    fixed_starting_price numeric(30,0),
    auction_length integer,
    starting_price numeric(30,0),
    want_token character varying(100),
    deployer character varying(100),
    receiver character varying(100),
    governance character varying(100),
    factory_address character varying(100),
    version character varying(20) DEFAULT '0.1.0'::character varying,
    decay_rate numeric(10,4),
    "timestamp" bigint DEFAULT EXTRACT(epoch FROM now()) NOT NULL
);


--
-- Name: TABLE auctions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auctions IS 'Main auction contracts table - one entry per deployed auction contract';


--
-- Name: enabled_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.enabled_tokens (
    auction_address character varying(100) NOT NULL,
    chain_id integer DEFAULT 1 NOT NULL,
    token_address character varying(100) NOT NULL,
    enabled_at bigint NOT NULL,
    enabled_at_block bigint NOT NULL,
    enabled_at_tx_hash character varying(100) NOT NULL
);


--
-- Name: indexer_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.indexer_state (
    id integer NOT NULL,
    chain_id integer NOT NULL,
    factory_address character varying(100) NOT NULL,
    factory_type character varying(10) NOT NULL,
    last_indexed_block integer DEFAULT 0 NOT NULL,
    start_block integer DEFAULT 0,
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: COLUMN indexer_state.start_block; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.indexer_state.start_block IS 'Starting block for factory indexing (can be NULL if factory not configured yet)';


--
-- Name: indexer_state_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.indexer_state_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: indexer_state_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.indexer_state_id_seq OWNED BY public.indexer_state.id;


--
-- Name: rounds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rounds (
    auction_address character varying(100) NOT NULL,
    chain_id integer DEFAULT 1 NOT NULL,
    round_id integer NOT NULL,
    from_token character varying(100) NOT NULL,
    initial_available numeric(78,18) NOT NULL,
    available_amount numeric(78,18),
    total_takes integer DEFAULT 0,
    total_volume_sold numeric(78,18) DEFAULT 0,
    progress_percentage numeric(5,2) DEFAULT 0,
    block_number bigint NOT NULL,
    transaction_hash character varying(200) NOT NULL,
    kicked_at bigint NOT NULL,
    "timestamp" bigint DEFAULT EXTRACT(epoch FROM now()) NOT NULL,
    round_start bigint,
    round_end bigint
);


--
-- Name: TABLE rounds; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.rounds IS 'Tracks individual rounds within Auctions, created by kick events. round_start/round_end are populated by indexer.';


--
-- Name: COLUMN rounds.transaction_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rounds.transaction_hash IS 'Transaction hash for the kick event (up to 200 chars for various networks)';


--
-- Name: COLUMN rounds.kicked_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rounds.kicked_at IS 'Unix timestamp when round was kicked (blockchain time)';


--
-- Name: COLUMN rounds.round_start; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rounds.round_start IS 'Unix timestamp when round started (same as kicked_at)';


--
-- Name: COLUMN rounds.round_end; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rounds.round_end IS 'Unix timestamp when round ends (round_start + auction_length)';


--
-- Name: takes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.takes (
    take_id character varying(200) NOT NULL,
    auction_address character varying(100) NOT NULL,
    chain_id integer DEFAULT 1 NOT NULL,
    round_id integer NOT NULL,
    take_seq integer NOT NULL,
    taker character varying(100) NOT NULL,
    from_token character varying(100) NOT NULL,
    to_token character varying(100) NOT NULL,
    amount_taken numeric(78,18) NOT NULL,
    amount_paid numeric(78,18) NOT NULL,
    price numeric(78,18) NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    seconds_from_round_start integer NOT NULL,
    block_number bigint NOT NULL,
    transaction_hash character varying(200) NOT NULL,
    log_index integer NOT NULL,
    gas_price numeric(20,9),
    base_fee numeric(20,9),
    priority_fee numeric(20,9),
    gas_used numeric(20,0),
    transaction_fee_eth numeric(20,18)
);


--
-- Name: TABLE takes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.takes IS 'Tracks individual takes within rounds, created by take events';


--
-- Name: COLUMN takes."timestamp"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.takes."timestamp" IS 'Unix timestamp of transaction (blockchain time)';


--
-- Name: COLUMN takes.transaction_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.takes.transaction_hash IS 'Transaction hash for the take event (up to 200 chars for various networks)';


--
-- Name: COLUMN takes.gas_price; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.takes.gas_price IS 'Gas price in Gwei (human readable)';


--
-- Name: COLUMN takes.base_fee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.takes.base_fee IS 'Base fee in Gwei (human readable, from EIP-1559)';


--
-- Name: COLUMN takes.priority_fee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.takes.priority_fee IS 'Priority fee in Gwei (0 for legacy transactions)';


--
-- Name: COLUMN takes.gas_used; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.takes.gas_used IS 'Total gas used by the transaction';


--
-- Name: COLUMN takes.transaction_fee_eth; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.takes.transaction_fee_eth IS 'Total transaction fee paid in ETH (human readable)';


--
-- Name: token_prices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token_prices (
    id integer NOT NULL,
    chain_id integer NOT NULL,
    block_number bigint NOT NULL,
    token_address character varying(100) NOT NULL,
    price_usd numeric(40,18) NOT NULL,
    "timestamp" bigint NOT NULL,
    source character varying(50) DEFAULT 'ypricemagic'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    txn_timestamp bigint
);


--
-- Name: TABLE token_prices; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.token_prices IS 'Historical token prices in USD from various sources';


--
-- Name: COLUMN token_prices.price_usd; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.token_prices.price_usd IS 'Token price in USD with high precision';


--
-- Name: COLUMN token_prices.source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.token_prices.source IS 'Price data source: ypricemagic, chainlink, coingecko, etc.';


--
-- Name: COLUMN token_prices.txn_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.token_prices.txn_timestamp IS 'Unix timestamp from the blockchain transaction that generated this price request';


--
-- Name: tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tokens (
    id integer NOT NULL,
    address character varying(100) NOT NULL,
    symbol character varying(50),
    name character varying(200),
    decimals integer,
    chain_id integer DEFAULT 1 NOT NULL,
    first_seen timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    "timestamp" bigint
);


--
-- Name: TABLE tokens; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.tokens IS 'Token metadata cache for display purposes across multiple chains';


--
-- Name: outbox_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbox_events (
    id bigint NOT NULL,
    type character varying(50) NOT NULL,
    chain_id integer NOT NULL,
    block_number bigint NOT NULL,
    tx_hash character varying(100) NOT NULL,
    log_index integer NOT NULL,
    auction_address character varying(100),
    round_id integer,
    from_token character varying(100),
    want_token character varying(100),
    "timestamp" bigint NOT NULL,
    payload_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    uniq character varying(200) NOT NULL,
    ver integer DEFAULT 1 NOT NULL,
    published_at timestamp with time zone,
    retries integer DEFAULT 0,
    last_error text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE outbox_events; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.outbox_events IS 'Outbox pattern for reliable event publishing to Redis Streams';


--
-- Name: outbox_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.outbox_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: outbox_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.outbox_events_id_seq OWNED BY public.outbox_events.id;


--
-- Name: price_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_requests (
    id integer NOT NULL,
    chain_id integer NOT NULL,
    block_number bigint NOT NULL,
    token_address character varying(100) NOT NULL,
    request_type character varying(50) DEFAULT 'take'::character varying NOT NULL,
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    txn_timestamp bigint,
    price_source character varying(50) DEFAULT 'all'::character varying,
    retries integer DEFAULT 0,
    last_error text,
    auction_address character varying(100),
    round_id integer
);


--
-- Name: TABLE price_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.price_requests IS 'Price requests for token pricing services';


--
-- Name: price_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.price_requests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: price_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.price_requests_id_seq OWNED BY public.price_requests.id;


--
-- Name: token_prices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.token_prices_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: token_prices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.token_prices_id_seq OWNED BY public.token_prices.id;


--
-- Name: tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tokens_id_seq OWNED BY public.tokens.id;


--
-- Name: auctions auctions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auctions
    ADD CONSTRAINT auctions_pkey PRIMARY KEY (auction_address, chain_id);


--
-- Name: enabled_tokens enabled_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enabled_tokens
    ADD CONSTRAINT enabled_tokens_pkey PRIMARY KEY (auction_address, chain_id, token_address);


--
-- Name: indexer_state indexer_state_chain_id_factory_address_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indexer_state
    ADD CONSTRAINT indexer_state_chain_id_factory_address_key UNIQUE (chain_id, factory_address);


--
-- Name: indexer_state indexer_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indexer_state
    ADD CONSTRAINT indexer_state_pkey PRIMARY KEY (id);


--
-- Name: rounds rounds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rounds
    ADD CONSTRAINT rounds_pkey PRIMARY KEY (auction_address, chain_id, round_id);


--
-- Name: takes takes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.takes
    ADD CONSTRAINT takes_pkey PRIMARY KEY (take_id, "timestamp");


--
-- Name: token_prices token_prices_chain_id_block_number_token_address_source_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_prices
    ADD CONSTRAINT token_prices_chain_id_block_number_token_address_source_key UNIQUE (chain_id, block_number, token_address, source);


--
-- Name: token_prices token_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_prices
    ADD CONSTRAINT token_prices_pkey PRIMARY KEY (id);


--
-- Name: tokens tokens_address_chain_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT tokens_address_chain_id_key UNIQUE (address, chain_id);


--
-- Name: tokens tokens_address_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT tokens_address_key UNIQUE (address);


--
-- Name: tokens tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT tokens_pkey PRIMARY KEY (id);


--
-- Name: outbox_events outbox_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT outbox_events_pkey PRIMARY KEY (id);


--
-- Name: outbox_events outbox_events_uniq_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT outbox_events_uniq_key UNIQUE (uniq);


--
-- Name: price_requests price_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_requests
    ADD CONSTRAINT price_requests_pkey PRIMARY KEY (id);


--
-- Name: price_requests price_requests_chain_id_block_number_token_address_reque; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_requests
    ADD CONSTRAINT price_requests_chain_id_block_number_token_address_reque UNIQUE (chain_id, block_number, token_address, request_type);


--
-- Name: idx_auctions_address_chain; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_auctions_address_chain ON public.auctions USING btree (auction_address, chain_id);


--
-- Name: idx_enabled_tokens_auction_chain_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_enabled_tokens_auction_chain_token ON public.enabled_tokens USING btree (auction_address, chain_id, token_address);


--
-- Name: idx_indexer_state_chain_factory; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_indexer_state_chain_factory ON public.indexer_state USING btree (chain_id, factory_address);


--
-- Name: idx_takes_chain; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_takes_chain ON public.takes USING btree (chain_id);


--
-- Name: idx_takes_chain_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_takes_chain_timestamp ON public.takes USING btree (chain_id, "timestamp" DESC);


--
-- Name: idx_takes_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_takes_recent ON public.takes USING btree ("timestamp" DESC, auction_address, round_id, take_seq);


--
-- Name: idx_takes_round; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_takes_round ON public.takes USING btree (auction_address, chain_id, round_id);


--
-- Name: idx_takes_taker; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_takes_taker ON public.takes USING btree (taker);


--
-- Name: idx_takes_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_takes_timestamp ON public.takes USING btree ("timestamp");


--
-- Name: idx_takes_tx_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_takes_tx_hash ON public.takes USING btree (transaction_hash);


--
-- Name: idx_takes_unique_chain_tx_log_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_takes_unique_chain_tx_log_ts ON public.takes USING btree (chain_id, transaction_hash, log_index, "timestamp");


--
-- Name: idx_outbox_chain_block; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbox_chain_block ON public.outbox_events USING btree (chain_id, block_number);


--
-- Name: idx_outbox_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbox_created ON public.outbox_events USING btree (created_at);


--
-- Name: idx_outbox_retries; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbox_retries ON public.outbox_events USING btree (retries) WHERE ((published_at IS NULL) AND (retries > 3));


--
-- Name: idx_outbox_unpublished; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbox_unpublished ON public.outbox_events USING btree (id) WHERE (published_at IS NULL);


--
-- Name: idx_price_requests_chain_block; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_price_requests_chain_block ON public.price_requests USING btree (chain_id, block_number);


--
-- Name: idx_price_requests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_price_requests_status ON public.price_requests USING btree (status) WHERE ((status)::text = 'pending'::text);


--
-- Name: indexer_state id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indexer_state ALTER COLUMN id SET DEFAULT nextval('public.indexer_state_id_seq'::regclass);


--
-- Name: outbox_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events ALTER COLUMN id SET DEFAULT nextval('public.outbox_events_id_seq'::regclass);


--
-- Name: price_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_requests ALTER COLUMN id SET DEFAULT nextval('public.price_requests_id_seq'::regclass);


--
-- Name: token_prices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_prices ALTER COLUMN id SET DEFAULT nextval('public.token_prices_id_seq'::regclass);


--
-- Name: tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens ALTER COLUMN id SET DEFAULT nextval('public.tokens_id_seq'::regclass);


--
-- PostgreSQL database dump complete
--



-- =============================================================================
-- DATABASE VIEWS (restored after schema sync)
-- =============================================================================

-- Active auction rounds view
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
    ar.progress_percentage,
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

-- Recent takes view
CREATE VIEW recent_takes AS
SELECT 
    als.take_id,
    als.auction_address,
    als.chain_id,
    als.round_id,
    als.take_seq,
    als.taker,
    als.from_token,
    als.to_token,
    als.amount_taken,
    als.amount_paid,
    als.price,
    als.timestamp,
    als.seconds_from_round_start,
    als.block_number,
    als.transaction_hash,
    als.log_index,
    ar.kicked_at AS round_kicked_at,
    ahp.want_token,
    t1.symbol AS from_token_symbol,
    t1.name AS from_token_name,
    t1.decimals AS from_token_decimals,
    t2.symbol AS to_token_symbol,
    t2.name AS to_token_name,
    t2.decimals AS to_token_decimals
FROM takes als
JOIN rounds ar ON als.auction_address = ar.auction_address 
    AND als.chain_id = ar.chain_id 
    AND als.round_id = ar.round_id
JOIN auctions ahp ON als.auction_address = ahp.auction_address 
    AND als.chain_id = ahp.chain_id
LEFT JOIN tokens t1 ON als.from_token = t1.address 
    AND als.chain_id = t1.chain_id
LEFT JOIN tokens t2 ON als.to_token = t2.address 
    AND als.chain_id = t2.chain_id
ORDER BY als.timestamp DESC;

-- VW_TAKES view (API compatibility)
CREATE VIEW vw_takes AS
SELECT * FROM recent_takes;

-- VW_AUCTIONS view
CREATE VIEW vw_auctions AS
SELECT 
    a.auction_address,
    a.chain_id,
    a.want_token,
    a.deployer,
    a.price_update_interval,
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
    
    -- Progress calculation
    CASE 
        WHEN cr.initial_available > 0 AND cr.available_amount IS NOT NULL 
        THEN ROUND((1.0 - (cr.available_amount::DECIMAL / cr.initial_available::DECIMAL)) * 100, 2)
        ELSE 0.0 
    END as progress_percentage,
    
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

-- VW_TAKES_ENRICHED view
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
    -- USD calculations set to NULL (simplified version)
    NULL::NUMERIC as from_token_price_usd,
    NULL::NUMERIC as to_token_price_usd,
    NULL::NUMERIC as amount_taken_usd,
    NULL::NUMERIC as amount_paid_usd,
    NULL::NUMERIC as price_differential_usd,
    NULL::NUMERIC as price_differential_percent,
    NULL::NUMERIC as transaction_fee_usd
FROM takes t
LEFT JOIN rounds r ON t.auction_address = r.auction_address 
                  AND t.chain_id = r.chain_id 
                  AND t.round_id = r.round_id
LEFT JOIN tokens tf ON LOWER(tf.address) = LOWER(t.from_token) 
                   AND tf.chain_id = t.chain_id
LEFT JOIN tokens tt ON LOWER(tt.address) = LOWER(t.to_token) 
                   AND tt.chain_id = t.chain_id;

-- MV_TAKERS_SUMMARY materialized view
CREATE MATERIALIZED VIEW mv_takers_summary AS
WITH taker_base_stats AS (
    SELECT 
        t.taker,
        COUNT(*) as total_takes,
        COUNT(DISTINCT t.auction_address) as unique_auctions,
        COUNT(DISTINCT t.chain_id) as unique_chains,
        COALESCE(SUM(t.amount_taken_usd), 0) as total_volume_usd,
        AVG(t.amount_taken_usd) as avg_take_size_usd,
        COALESCE(SUM(t.price_differential_usd), 0) as total_profit_usd,
        AVG(t.price_differential_usd) as avg_profit_per_take_usd,
        MIN(t.timestamp) as first_take,
        MAX(t.timestamp) as last_take,
        ARRAY_AGG(DISTINCT t.chain_id ORDER BY t.chain_id) as active_chains,
        -- Recent activity metrics
        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days') as takes_last_7d,
        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days') as takes_last_30d,
        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days'), 0) as volume_last_7d,
        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days'), 0) as volume_last_30d,
        -- Success rate (positive profit)
        COUNT(*) FILTER (WHERE t.price_differential_usd > 0) as profitable_takes,
        COUNT(*) FILTER (WHERE t.price_differential_usd < 0) as unprofitable_takes
    FROM vw_takes_enriched t
    WHERE t.taker IS NOT NULL
    GROUP BY t.taker
)
SELECT 
    *,
    -- Rankings
    RANK() OVER (ORDER BY total_takes DESC) as rank_by_takes,
    RANK() OVER (ORDER BY total_volume_usd DESC NULLS LAST) as rank_by_volume,
    RANK() OVER (ORDER BY total_profit_usd DESC NULLS LAST) as rank_by_profit,
    -- Success rate calculation
    CASE 
        WHEN (profitable_takes + unprofitable_takes) > 0 
        THEN profitable_takes::DECIMAL / (profitable_takes + unprofitable_takes) * 100
        ELSE NULL
    END as success_rate_percent
FROM taker_base_stats;

-- Indexes for materialized view
CREATE UNIQUE INDEX idx_mv_takers_summary_taker ON mv_takers_summary(taker);
CREATE INDEX idx_mv_takers_summary_volume ON mv_takers_summary(total_volume_usd DESC NULLS LAST);
CREATE INDEX idx_mv_takers_summary_takes ON mv_takers_summary(total_takes DESC);

-- Helper function to refresh materialized views
CREATE OR REPLACE FUNCTION refresh_taker_analytics()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_takers_summary;
    RAISE NOTICE 'Refreshed mv_takers_summary materialized view';
END;
$$ LANGUAGE plpgsql;

-- Comments
COMMENT ON VIEW active_auction_rounds IS 'Shows currently active auction rounds with calculated time remaining and auction parameters';
COMMENT ON VIEW recent_takes IS 'Recent takes with token metadata and round information for API consumption';
COMMENT ON VIEW vw_takes IS 'Alias for recent_takes view (API compatibility)';
COMMENT ON VIEW vw_auctions IS 'Comprehensive auction view with current round information';
COMMENT ON VIEW vw_takes_enriched IS 'Enhanced takes view with token/round context and gas information';
COMMENT ON MATERIALIZED VIEW mv_takers_summary IS 'Pre-calculated taker statistics with rankings and activity metrics';

