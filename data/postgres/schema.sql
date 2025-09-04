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
-- PostgreSQL database dump complete
--

