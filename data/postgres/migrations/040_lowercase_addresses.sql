-- 040_lowercase_addresses.sql
-- Normalize address-like columns to lowercase on write and backfill existing rows.

BEGIN;

-- Backfill existing data to lowercase
UPDATE auctions SET auction_address = LOWER(auction_address) WHERE auction_address IS NOT NULL;
UPDATE auctions SET want_token = LOWER(want_token) WHERE want_token IS NOT NULL;

UPDATE tokens SET address = LOWER(address) WHERE address IS NOT NULL;

UPDATE rounds SET auction_address = LOWER(auction_address) WHERE auction_address IS NOT NULL;
UPDATE rounds SET from_token = LOWER(from_token) WHERE from_token IS NOT NULL;

UPDATE enabled_tokens SET auction_address = LOWER(auction_address) WHERE auction_address IS NOT NULL;
UPDATE enabled_tokens SET token_address = LOWER(token_address) WHERE token_address IS NOT NULL;

UPDATE takes SET auction_address = LOWER(auction_address) WHERE auction_address IS NOT NULL;
UPDATE takes SET taker = LOWER(taker) WHERE taker IS NOT NULL;
UPDATE takes SET from_token = LOWER(from_token) WHERE from_token IS NOT NULL;
UPDATE takes SET to_token = LOWER(to_token) WHERE to_token IS NOT NULL;

-- Triggers to enforce lowercase on writes

CREATE OR REPLACE FUNCTION enforce_lowercase_auctions() RETURNS trigger AS $$
BEGIN
  IF NEW.auction_address IS NOT NULL THEN NEW.auction_address := LOWER(NEW.auction_address); END IF;
  IF NEW.want_token IS NOT NULL THEN NEW.want_token := LOWER(NEW.want_token); END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER auctions_lowercase_trg
  BEFORE INSERT OR UPDATE ON auctions
  FOR EACH ROW EXECUTE FUNCTION enforce_lowercase_auctions();

CREATE OR REPLACE FUNCTION enforce_lowercase_tokens() RETURNS trigger AS $$
BEGIN
  IF NEW.address IS NOT NULL THEN NEW.address := LOWER(NEW.address); END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER tokens_lowercase_trg
  BEFORE INSERT OR UPDATE ON tokens
  FOR EACH ROW EXECUTE FUNCTION enforce_lowercase_tokens();

CREATE OR REPLACE FUNCTION enforce_lowercase_rounds() RETURNS trigger AS $$
BEGIN
  IF NEW.auction_address IS NOT NULL THEN NEW.auction_address := LOWER(NEW.auction_address); END IF;
  IF NEW.from_token IS NOT NULL THEN NEW.from_token := LOWER(NEW.from_token); END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER rounds_lowercase_trg
  BEFORE INSERT OR UPDATE ON rounds
  FOR EACH ROW EXECUTE FUNCTION enforce_lowercase_rounds();

CREATE OR REPLACE FUNCTION enforce_lowercase_enabled_tokens() RETURNS trigger AS $$
BEGIN
  IF NEW.auction_address IS NOT NULL THEN NEW.auction_address := LOWER(NEW.auction_address); END IF;
  IF NEW.token_address IS NOT NULL THEN NEW.token_address := LOWER(NEW.token_address); END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER enabled_tokens_lowercase_trg
  BEFORE INSERT OR UPDATE ON enabled_tokens
  FOR EACH ROW EXECUTE FUNCTION enforce_lowercase_enabled_tokens();

CREATE OR REPLACE FUNCTION enforce_lowercase_takes() RETURNS trigger AS $$
BEGIN
  IF NEW.auction_address IS NOT NULL THEN NEW.auction_address := LOWER(NEW.auction_address); END IF;
  IF NEW.taker IS NOT NULL THEN NEW.taker := LOWER(NEW.taker); END IF;
  IF NEW.from_token IS NOT NULL THEN NEW.from_token := LOWER(NEW.from_token); END IF;
  IF NEW.to_token IS NOT NULL THEN NEW.to_token := LOWER(NEW.to_token); END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER takes_lowercase_trg
  BEFORE INSERT OR UPDATE ON takes
  FOR EACH ROW EXECUTE FUNCTION enforce_lowercase_takes();

COMMIT;

