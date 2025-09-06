-- Add index to accelerate latest-per-source aggregation on token_prices

BEGIN;

CREATE INDEX IF NOT EXISTS idx_token_prices_source_ts
ON public.token_prices (source, timestamp DESC);

COMMIT;

