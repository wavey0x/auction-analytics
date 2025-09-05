-- Unified migration wrapper for production or ad-hoc use
-- Delegates to the canonical migration file so there is a single source of truth.
\echo 'Applying canonical vw_auctions view migration...'
\i data/postgres/migrations/033_create_vw_auctions_view.sql
\echo 'Done.'

