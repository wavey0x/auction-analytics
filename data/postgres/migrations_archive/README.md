# Archived Migration Files

These migration files have been archived because we now use a **complete schema approach** instead of incremental migrations.

## What changed

- **Before**: Multiple incremental migration files (009-032) that had to be run in sequence
- **After**: Single `complete_schema.sql` that creates the entire database structure in one shot

## Files archived

These were the old incremental migrations:
- `009_add_outbox_events.sql` - Added outbox events table
- `021_normalize_total_takes.sql` - Normalized takes counting
- `022_add_gas_tracking.sql` - Added gas tracking columns
- `023_remove_price_request_constraints.sql` - Made price request constraints flexible
- `024_add_taker_analytics.sql` - Added taker analytics features
- `024_add_transaction_timestamps.sql` - Added transaction timestamps
- `025_taker_indexes.sql` - Added taker performance indexes
- `026_refactor_usd_calculations.sql` - Refactored USD calculations
- `027_normalize_tx_hash_prefix.sql` - Normalized transaction hash prefixes
- `028_stats_perf_indexes.sql` - Added statistics performance indexes
- `029_add_indexer_state_columns.sql` - Added indexer state columns
- `030_add_missing_indexer_tables.sql` - Added missing indexer tables
- `031_add_missing_auctions_columns.sql` - Added missing auction columns
- `032_fix_indexer_schema_issues.sql` - Fixed indexer schema compatibility

## New approach

All the functionality from these migrations is now included in:
- `/data/postgres/complete_schema.sql` - Complete database setup
- `/setup_database.sh` - One-shot database setup script

## For new deployments

Simply run:
```bash
./setup_database.sh --mode=prod
```

This creates a complete, working database with all features from the archived migrations.

## For existing deployments

If you're upgrading an existing deployment, you can either:
1. **Recommended**: Use the new complete schema setup
2. **Alternative**: Continue using the old migration approach (files are archived here)

The complete schema includes all improvements and fixes from the migration history.