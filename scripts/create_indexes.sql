-- High-impact indexes for price lookups and take filters

-- Token prices: speed up closest block <= X per token/chain
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_token_prices_chain_token_block_desc
  ON token_prices (chain_id, LOWER(token_address), block_number DESC);

-- Takes per taker history (most recent first)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_takes_taker_ts
  ON takes (LOWER(taker), timestamp DESC);

-- Takes per auction (most recent first)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_takes_auction_chain_ts
  ON takes (LOWER(auction_address), chain_id, timestamp DESC);

-- Takes point lookup within a round
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_takes_auction_chain_round_seq
  ON takes (LOWER(auction_address), chain_id, round_id, take_seq);

-- Rounds metadata join
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rounds_auction_chain_round
  ON rounds (LOWER(auction_address), chain_id, round_id);

-- Tokens metadata join
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tokens_chain_lower_addr
  ON tokens (chain_id, LOWER(address));

