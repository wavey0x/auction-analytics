-- Drops the takers materialized view and updates refresh helper to a no-op.

BEGIN;

-- Drop MV if present (and dependent indexes)
DROP MATERIALIZED VIEW IF EXISTS mv_takers_summary CASCADE;

-- Optional: replace refresh function to avoid future failures
CREATE OR REPLACE FUNCTION refresh_taker_analytics() RETURNS void AS $$
BEGIN
    RAISE NOTICE 'vw_takers_summary is a regular view; no refresh needed.';
END;
$$ LANGUAGE plpgsql;

-- Optional: if you have a function targeting vw_takers_summary as a MV, neutralize it
CREATE OR REPLACE FUNCTION refresh_takers_summary() RETURNS void AS $$
BEGIN
    RAISE NOTICE 'vw_takers_summary is a regular view; no refresh needed.';
END;
$$ LANGUAGE plpgsql;

COMMIT;

