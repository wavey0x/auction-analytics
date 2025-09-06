-- Add performance indexes for mv_takes_enriched to speed recent queries

BEGIN;

-- Recent first scans
CREATE INDEX IF NOT EXISTS idx_mv_takes_enriched_ts
ON public.mv_takes_enriched (timestamp DESC);

-- Chain-scoped recent scans
CREATE INDEX IF NOT EXISTS idx_mv_takes_enriched_chain_ts
ON public.mv_takes_enriched (chain_id, timestamp DESC);

COMMIT;

