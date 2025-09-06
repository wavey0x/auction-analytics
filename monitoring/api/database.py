#!/usr/bin/env python3
"""
Database connection and session management for FastAPI.
"""

import os
import asyncio
import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional
from dotenv import load_dotenv
from fastapi.encoders import jsonable_encoder
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from sqlalchemy import text

# Load environment variables from .env file
load_dotenv("../../.env")

logger = logging.getLogger(__name__)

# Helper functions for data serialization
def row_to_dict(row):
    """Convert database row to dictionary safely for JSON serialization"""
    if hasattr(row, '_mapping'):
        return dict(row._mapping)
    elif hasattr(row, '_asdict'):
        return row._asdict()
    elif isinstance(row, dict):
        return row
    else:
        # Fallback for other types
        return dict(row)

def format_timestamp(value):
    """Convert timestamp to ISO format safely"""
    if value is None:
        return None
    elif isinstance(value, int):
        return datetime.fromtimestamp(value, tz=timezone.utc).isoformat()
    elif hasattr(value, 'isoformat'):
        return value.isoformat()
    else:
        return str(value)

# Database configuration
DATABASE_URL = os.getenv(
    "DATABASE_URL", 
    "postgresql://postgres@localhost:5432/auction"  # Fixed default to use correct user
)

# Convert to async URL if needed
if DATABASE_URL.startswith("postgresql://"):
    ASYNC_DATABASE_URL = DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://")
else:
    ASYNC_DATABASE_URL = DATABASE_URL

# Create async engine
# Only enable SQL logging in debug mode (set SQL_DEBUG=true to enable)
sql_debug = os.getenv("SQL_DEBUG", "false").lower() == "true"
engine = create_async_engine(
    ASYNC_DATABASE_URL,
    echo=sql_debug,  # Enable SQL logging only when SQL_DEBUG=true
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,
    pool_recycle=3600,  # Recycle connections after 1 hour
)

# Create session factory
AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False
)

# SQLAlchemy base
Base = declarative_base()

async def get_db():
    """Dependency to get database session"""
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()

async def check_database_connection():
    """Check if database connection is working"""
    try:
        async with AsyncSessionLocal() as session:
            result = await session.execute(text("SELECT 1"))
            return result.scalar() == 1
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        return False


import time as _time

# Lightweight, in-process caches for repeated calls
_TABLES_CACHE: dict[str, float] = {}
_TABLES_CACHE_TTL = 60.0  # seconds
_ENRICHED_RELATION_CACHE: dict[str, float] = {}
_ENRICHED_RELATION_TTL = 60.0  # seconds
_TAKERS_SUMMARY_RELATION_CACHE: dict[str, float] = {}
_TAKERS_SUMMARY_RELATION_TTL = 60.0  # seconds

class DatabaseQueries:
    """Centralized database query methods for Auction structure"""
    
    @staticmethod
    async def _get_enriched_takes_relation(db: AsyncSession) -> str:
        """Return name of enriched takes relation, preferring materialized view.

        Checks for mv_takes_enriched via pg_matviews, else falls back to vw_takes_enriched.
        Caches the result briefly to avoid repeated catalog lookups.
        """
        now = _time.time()
        if _ENRICHED_RELATION_CACHE and now - next(iter(_ENRICHED_RELATION_CACHE.values())) < _ENRICHED_RELATION_TTL:
            return next(iter(_ENRICHED_RELATION_CACHE.keys()))

        rel = 'vw_takes_enriched'
        try:
            result = await db.execute(text("SELECT 1 FROM pg_matviews WHERE schemaname='public' AND matviewname='mv_takes_enriched'"))
            if result.fetchone():
                rel = 'mv_takes_enriched'
        except Exception:
            rel = 'vw_takes_enriched'
        
        _ENRICHED_RELATION_CACHE.clear()
        _ENRICHED_RELATION_CACHE[rel] = now
        return rel

    @staticmethod
    async def _get_takers_summary_relation(db: AsyncSession) -> str:
        """Return preferred takers summary relation; prefer MV when available.

        Checks for mv_takers_summary in pg_matviews, otherwise falls back to vw_takers_summary.
        Caches briefly to avoid repeated catalog scans.
        """
        now = _time.time()
        if _TAKERS_SUMMARY_RELATION_CACHE and now - next(iter(_TAKERS_SUMMARY_RELATION_CACHE.values())) < _TAKERS_SUMMARY_RELATION_TTL:
            return next(iter(_TAKERS_SUMMARY_RELATION_CACHE.keys()))

        rel = 'vw_takers_summary'
        try:
            result = await db.execute(text("SELECT 1 FROM pg_matviews WHERE schemaname='public' AND matviewname='mv_takers_summary'"))
            if result.fetchone():
                rel = 'mv_takers_summary'
        except Exception:
            rel = 'vw_takers_summary'

        _TAKERS_SUMMARY_RELATION_CACHE.clear()
        _TAKERS_SUMMARY_RELATION_CACHE[rel] = now
        return rel
    
    @staticmethod
    async def get_auctions(db: AsyncSession, active_only: bool = False, chain_id: int = None, limit: int = None, offset: int = None):
        """Get auctions with optional active filter and pagination at the database level"""
        chain_filter = "AND vw.chain_id = :chain_id" if chain_id else ""
        
        limit_clause = " LIMIT :limit" if limit is not None else ""
        offset_clause = " OFFSET :offset" if offset is not None else ""

        base_select = """
            SELECT 
                vw.auction_address,
                vw.chain_id,
                vw.want_token,
                vw.want_token_symbol,
                vw.want_token_name,
                vw.want_token_decimals,
                vw.current_round_id,
                vw.has_active_round,
                vw.current_available,
                vw.last_kicked_timestamp,
                vw.last_kicked,
                vw.initial_available,
                vw.auction_length,
                vw.update_interval,
                a.decay_rate,
                r.from_token as current_round_from_token,
                r.transaction_hash as current_round_transaction_hash,
                r.block_number as current_round_block_number,
                tp_from.price_usd as from_token_price_usd,
                tp_want.price_usd as want_token_price_usd,
                ft.symbol as from_token_symbol,
                ft.name as from_token_name,
                ft.decimals as from_token_decimals
            FROM vw_auctions vw
            JOIN auctions a ON vw.auction_address = a.auction_address AND vw.chain_id = a.chain_id
            LEFT JOIN rounds r ON vw.auction_address = r.auction_address 
                AND vw.chain_id = r.chain_id 
                AND vw.current_round_id = r.round_id
            LEFT JOIN tokens ft ON LOWER(r.from_token) = LOWER(ft.address) AND r.chain_id = ft.chain_id
            -- Prefer ypricemagic > chainlink > others; pick latest created_at when ties
            LEFT JOIN LATERAL (
                SELECT tp.price_usd
                FROM token_prices tp
                WHERE tp.chain_id = vw.chain_id
                  AND tp.block_number = r.block_number
                  AND LOWER(tp.token_address) = LOWER(r.from_token)
                ORDER BY CASE tp.source WHEN 'ypricemagic' THEN 0 WHEN 'chainlink' THEN 1 ELSE 2 END, tp.created_at DESC
                LIMIT 1
            ) tp_from ON true
            LEFT JOIN LATERAL (
                SELECT tp.price_usd
                FROM token_prices tp
                WHERE tp.chain_id = vw.chain_id
                  AND tp.block_number = r.block_number
                  AND LOWER(tp.token_address) = LOWER(vw.want_token)
                ORDER BY CASE tp.source WHEN 'ypricemagic' THEN 0 WHEN 'chainlink' THEN 1 ELSE 2 END, tp.created_at DESC
                LIMIT 1
            ) tp_want ON true
        """
        if active_only:
            query = text(f"""
                {base_select}
                WHERE vw.has_active_round = TRUE
                {chain_filter}
                ORDER BY vw.last_kicked DESC NULLS LAST{limit_clause}{offset_clause}
            """)
        else:
            query = text(f"""
                {base_select}
                WHERE 1=1
                {chain_filter}
                ORDER BY vw.last_kicked DESC NULLS LAST{limit_clause}{offset_clause}
            """)
        
        params = {"chain_id": chain_id} if chain_id else {}
        if limit is not None:
            params["limit"] = limit
        if offset is not None:
            params["offset"] = offset
        result = await db.execute(query, params)
        return result.fetchall()

    @staticmethod
    async def count_auctions(db: AsyncSession, active_only: bool = False, chain_id: int = None):
        """Get total count of auctions for pagination"""
        chain_filter = "AND chain_id = :chain_id" if chain_id else ""
        if active_only:
            query = text(f"""
                SELECT COUNT(*)
                FROM vw_auctions
                WHERE has_active_round = TRUE
                {chain_filter}
            """)
        else:
            query = text(f"""
                SELECT COUNT(*)
                FROM vw_auctions
                WHERE 1=1
                {chain_filter}
            """)
        params = {"chain_id": chain_id} if chain_id else {}
        result = await db.execute(query, params)
        return int(result.scalar() or 0)
    
    @staticmethod
    async def get_enabled_token_addresses(db: AsyncSession, auction_address: str, chain_id: int):
        """Get enabled token addresses for a specific auction (addresses only)"""
        query = text("""
            SELECT token_address
            FROM enabled_tokens
            WHERE LOWER(auction_address) = LOWER(:auction_address) AND chain_id = :chain_id
            ORDER BY enabled_at ASC
        """)
        result = await db.execute(query, {"auction_address": auction_address, "chain_id": chain_id})
        return [row.token_address for row in result.fetchall()]
    
    @staticmethod
    async def get_auction_details(db: AsyncSession, auction_address: str, chain_id: int = None):
        """Get detailed information about a specific Auction.

        Includes current round token metadata and transaction hash via joins.
        """
        chain_filter = "AND vw.chain_id = :chain_id" if chain_id else ""
        
        query = text(f"""
            SELECT 
                vw.*, 
                a.timestamp as deployed_timestamp, 
                a.decay_rate, 
                a.governance,
                r.from_token as current_round_from_token,
                r.transaction_hash as current_round_transaction_hash,
                r.block_number as current_round_block_number,
                tp_from.price_usd as from_token_price_usd,
                tp_want.price_usd as want_token_price_usd,
                ft.symbol as from_token_symbol,
                ft.name as from_token_name,
                ft.decimals as from_token_decimals
            FROM vw_auctions vw
            JOIN auctions a 
                ON vw.auction_address = a.auction_address 
               AND vw.chain_id = a.chain_id
            LEFT JOIN rounds r 
                ON vw.auction_address = r.auction_address 
               AND vw.chain_id = r.chain_id 
               AND vw.current_round_id = r.round_id
            LEFT JOIN tokens ft 
                ON LOWER(r.from_token) = LOWER(ft.address) 
               AND r.chain_id = ft.chain_id
            LEFT JOIN LATERAL (
                SELECT tp.price_usd
                FROM token_prices tp
                WHERE tp.chain_id = vw.chain_id
                  AND tp.block_number = r.block_number
                  AND LOWER(tp.token_address) = LOWER(r.from_token)
                ORDER BY CASE tp.source WHEN 'ypricemagic' THEN 0 WHEN 'chainlink' THEN 1 ELSE 2 END, tp.created_at DESC
                LIMIT 1
            ) tp_from ON true
            LEFT JOIN LATERAL (
                SELECT tp.price_usd
                FROM token_prices tp
                WHERE tp.chain_id = vw.chain_id
                  AND tp.block_number = r.block_number
                  AND LOWER(tp.token_address) = LOWER(vw.want_token)
                ORDER BY CASE tp.source WHEN 'ypricemagic' THEN 0 WHEN 'chainlink' THEN 1 ELSE 2 END, tp.created_at DESC
                LIMIT 1
            ) tp_want ON true
            WHERE LOWER(vw.auction_address) = LOWER(:auction_address)
            {chain_filter}
            LIMIT 1
        """)
        
        params = {"auction_address": auction_address}
        if chain_id:
            params["chain_id"] = chain_id
            
        result = await db.execute(query, params)
        return result.fetchone()

    @staticmethod
    async def get_enabled_tokens(db: AsyncSession, auction_address: str, chain_id: int):
        """Get enabled tokens for a specific auction with token metadata"""
        query = text("""
            SELECT 
                et.token_address,
                COALESCE(t.symbol, 'Unknown') as token_symbol,
                COALESCE(t.name, 'Unknown') as token_name,
                COALESCE(t.decimals, 18) as token_decimals,
                et.chain_id
            FROM enabled_tokens et
            LEFT JOIN tokens t 
                ON LOWER(et.token_address) = LOWER(t.address) 
                AND et.chain_id = t.chain_id
            WHERE LOWER(et.auction_address) = LOWER(:auction_address)
            AND et.chain_id = :chain_id
            ORDER BY et.enabled_at ASC
        """)
        
        params = {"auction_address": auction_address, "chain_id": chain_id}
        result = await db.execute(query, params)
        return [dict(row._mapping) for row in result.fetchall()]

    @staticmethod
    async def get_enabled_tokens_for_addresses(db: AsyncSession, chain_id: int, auction_addresses: list[str]):
        """Bulk fetch enabled tokens (with metadata) for many auctions on a chain.

        Args:
            chain_id: chain id
            auction_addresses: list of lowercase addresses
        Returns rows with: auction_address, token_address, token_symbol, token_name, token_decimals, chain_id
        """
        if not auction_addresses:
            return []
        query = text("""
            SELECT 
                et.auction_address,
                et.token_address,
                COALESCE(t.symbol, 'Unknown') as token_symbol,
                COALESCE(t.name, 'Unknown') as token_name,
                COALESCE(t.decimals, 18) as token_decimals,
                et.chain_id
            FROM enabled_tokens et
            LEFT JOIN tokens t 
                ON LOWER(et.token_address) = LOWER(t.address)
               AND et.chain_id = t.chain_id
            WHERE et.chain_id = :chain_id
              AND LOWER(et.auction_address) = ANY(:addresses)
            ORDER BY et.auction_address, et.enabled_at ASC
        """)
        params = {
            "chain_id": chain_id,
            "addresses": [addr.lower() for addr in auction_addresses],
        }
        result = await db.execute(query, params)
        return [dict(row._mapping) for row in result.fetchall()]
    
    @staticmethod
    async def get_auction_rounds(db: AsyncSession, auction_address: str, from_token: str = None, chain_id: int = None, limit: int = 50, round_id: int = None):
        """Get round history for an Auction"""
        chain_filter = "AND ar.chain_id = :chain_id" if chain_id else ""
        token_filter = "AND ar.from_token = :from_token" if from_token else ""
        round_filter = "AND ar.round_id = :round_id" if round_id else ""
        
        query = text(f"""
            SELECT 
                ar.*,
                ahp.want_token,
                ahp.auction_length
            FROM rounds ar
            JOIN auctions ahp 
                ON LOWER(ar.auction_address) = LOWER(ahp.auction_address) 
                AND ar.chain_id = ahp.chain_id
            WHERE LOWER(ar.auction_address) = LOWER(:auction_address)
            {chain_filter}
            {token_filter}
            {round_filter}
            ORDER BY ar.round_id DESC
            LIMIT :limit
        """)
        
        params = {
            "auction_address": auction_address,
            "limit": limit
        }
        if chain_id:
            params["chain_id"] = chain_id
        if from_token:
            params["from_token"] = from_token
        if round_id:
            params["round_id"] = round_id
            
        result = await db.execute(query, params)
        return result.fetchall()

    @staticmethod
    async def get_auction_activity_stats(db: AsyncSession, auction_address: str, chain_id: int):
        """Get activity statistics for an auction"""
        query = text("""
            SELECT 
                COUNT(DISTINCT t.taker) as total_participants,
                COALESCE(SUM(CASE WHEN t.amount_paid_usd IS NOT NULL THEN t.amount_paid_usd::numeric ELSE 0 END), 0) as total_volume,
                COUNT(DISTINCT t.round_id) as total_rounds,
                COUNT(t.take_id) as total_takes
            FROM vw_takes_enriched t
            WHERE LOWER(t.auction_address) = LOWER(:auction_address)
            AND t.chain_id = :chain_id
        """)
        
        params = {"auction_address": auction_address, "chain_id": chain_id}
        result = await db.execute(query, params)
        return result.fetchone()
    
    @staticmethod
    async def get_auction_takes(db: AsyncSession, auction_address: str, round_id: int = None, chain_id: int = None, limit: int = 50, offset: int = 0):
        """Get takes history for an Auction using enhanced vw_takes view with USD prices"""
        chain_filter = "AND chain_id = :chain_id" if chain_id else ""
        round_filter = "AND round_id = :round_id" if round_id else ""
        
        # Get total count
        count_query = text(f"""
            SELECT COUNT(*) as total
            FROM vw_takes_enriched
            WHERE LOWER(auction_address) = LOWER(:auction_address)
            {chain_filter}
            {round_filter}
        """)
        
        # Get paginated data
        data_query = text(f"""
            SELECT 
                take_id,
                auction_address,
                chain_id,
                round_id,
                take_seq,
                taker,
                from_token,
                to_token,
                amount_taken,
                amount_paid,
                price,
                timestamp,
                seconds_from_round_start,
                block_number,
                transaction_hash,
                log_index,
                round_kicked_at,
                from_token_symbol,
                from_token_name,
                from_token_decimals,
                to_token_symbol,
                to_token_name,
                to_token_decimals,
                from_token_price_usd,
                to_token_price_usd AS want_token_price_usd,
                amount_taken_usd,
                amount_paid_usd,
                price_differential_usd,
                price_differential_percent
            FROM vw_takes_enriched
            WHERE LOWER(auction_address) = LOWER(:auction_address)
            {chain_filter}
            {round_filter}
            ORDER BY timestamp DESC
            LIMIT :limit OFFSET :offset
        """)
        
        params = {
            "auction_address": auction_address,
            "limit": limit,
            "offset": offset
        }
        if chain_id:
            params["chain_id"] = chain_id
        if round_id:
            params["round_id"] = round_id
        
        # Execute both queries
        count_result = await db.execute(count_query, {k: v for k, v in params.items() if k not in ['limit', 'offset']})
        data_result = await db.execute(data_query, params)
        
        total = count_result.scalar() or 0
        takes = data_result.fetchall()
        
        return {"takes": takes, "total": total}
    
    @staticmethod
    async def get_price_history(db: AsyncSession, auction_address: str, round_id: int = None, chain_id: int = None, hours: int = 24):
        """Get price history for an Auction round"""
        chain_filter = "AND ph.chain_id = :chain_id" if chain_id else ""
        round_filter = "AND ph.round_id = :round_id" if round_id else ""
        
        query = text(f"""
            SELECT 
                ph.timestamp,
                ph.price,
                ph.available_amount,
                ph.seconds_from_round_start,
                ph.round_id,
                ph.from_token
            FROM price_history ph
            WHERE LOWER(ph.auction_address) = LOWER(:auction_address)
            AND ph.timestamp >= NOW() - INTERVAL '{hours} hours'
            {chain_filter}
            {round_filter}
            ORDER BY ph.timestamp ASC
        """)
        
        params = {
            "auction_address": auction_address
        }
        if chain_id:
            params["chain_id"] = chain_id
        if round_id:
            params["round_id"] = round_id
            
        result = await db.execute(query, params)
        return result.fetchall()
    
    @staticmethod
    async def get_all_tokens(db: AsyncSession, chain_id: int = None):
        """Get all token information"""
        chain_filter = "WHERE chain_id = :chain_id" if chain_id else ""
        
        query = text(f"""
            SELECT address, symbol, name, decimals, chain_id
            FROM tokens
            {chain_filter}
            ORDER BY chain_id, symbol
        """)
        
        params = {"chain_id": chain_id} if chain_id else {}
        result = await db.execute(query, params)
        return result.fetchall()
    
    @staticmethod
    async def get_system_stats(db: AsyncSession, chain_id: int = None):
        """Get overall system statistics with optimized SQL and light caching.

        Optimizations:
        - Cache table-existence checks for a short TTL.
        - Use JOINs instead of IN-subqueries for better planner choices.
        - Optionally clamp USD volume to a recent time window via env STATS_VOLUME_DAYS.
        """
        try:
            now = _time.time()
            # Cache table existence (to avoid information_schema hits per request)
            existing_tables: set[str]
            if _TABLES_CACHE and now - next(iter(_TABLES_CACHE.values())) < _TABLES_CACHE_TTL:
                existing_tables = set(_TABLES_CACHE.keys())
            else:
                table_check_query = text("""
                    SELECT table_name 
                    FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                      AND table_name IN (
                        'auctions','rounds','takes','tokens',
                        'vw_takes','vw_takes_enriched','mv_takes_enriched'
                      )
                """)
                result = await db.execute(table_check_query)
                existing_tables = {row[0] for row in result.fetchall()}
                # Refresh cache timestamp values
                _TABLES_CACHE.clear()
                for t in existing_tables:
                    _TABLES_CACHE[t] = now

            params: dict = {}
            chain_filter_sql = ""
            if chain_id is not None:
                params["chain_id"] = chain_id
                chain_filter_sql = " AND a.chain_id = :chain_id"

            # total_auctions, unique_tokens
            auctions_count_sql = "0"
            tokens_count_sql = "0"
            if 'auctions' in existing_tables:
                auctions_count_sql = f"(SELECT COUNT(*) FROM auctions a{' WHERE a.chain_id = :chain_id' if chain_id is not None else ''})"
            if 'tokens' in existing_tables:
                tokens_count_sql = f"(SELECT COUNT(DISTINCT t.address) FROM tokens t{' WHERE t.chain_id = :chain_id' if chain_id is not None else ''})"

            # active_auctions and rounds_count
            active_auctions_sql = "0"
            rounds_count_sql = "0"
            if 'rounds' in existing_tables and 'auctions' in existing_tables:
                # Active when auction has an active round (within 24 hours AND tokens available)
                active_auctions_sql = (
                    "(SELECT COUNT(DISTINCT v.auction_address)"
                    "   FROM vw_auctions v JOIN auctions a"
                    "     ON LOWER(v.auction_address) = LOWER(a.auction_address) AND v.chain_id = a.chain_id"
                    f"  WHERE v.has_active_round = TRUE{chain_filter_sql})"
                )
                rounds_count_sql = (
                    "(SELECT COUNT(*) FROM rounds r JOIN auctions a"
                    "  ON LOWER(r.auction_address) = LOWER(a.auction_address) AND r.chain_id = a.chain_id"
                    f" WHERE 1=1{chain_filter_sql})"
                )

            # takes_count and participants_count
            takes_count_sql = "0"
            participants_count_sql = "0"
            if 'takes' in existing_tables and 'auctions' in existing_tables:
                takes_count_sql = (
                    "(SELECT COUNT(*) FROM takes t JOIN auctions a"
                    "  ON LOWER(t.auction_address) = LOWER(a.auction_address) AND t.chain_id = a.chain_id"
                    f" WHERE 1=1{chain_filter_sql})"
                )
                participants_count_sql = (
                    "(SELECT COUNT(DISTINCT t.taker) FROM takes t JOIN auctions a"
                    "  ON LOWER(t.auction_address) = LOWER(a.auction_address) AND t.chain_id = a.chain_id"
                    f" WHERE 1=1{chain_filter_sql})"
                )

            # total_volume_usd, with optional time window
            volume_usd_sql = "0"
            if ('mv_takes_enriched' in existing_tables or 'vw_takes_enriched' in existing_tables or 'vw_takes' in existing_tables) and 'auctions' in existing_tables:
                if 'mv_takes_enriched' in existing_tables:
                    view_name = 'mv_takes_enriched'
                else:
                    view_name = 'vw_takes_enriched' if 'vw_takes_enriched' in existing_tables else 'vw_takes'
                days = int(os.getenv('STATS_VOLUME_DAYS', os.getenv('DEV_STATS_VOLUME_DAYS', '7')))
                time_filter = ""
                if days and days > 0:
                    time_filter = f" AND t.timestamp >= NOW() - INTERVAL '{days} days'"
                volume_usd_sql = (
                    f"(SELECT COALESCE(SUM(t.amount_paid_usd), 0) FROM {view_name} t JOIN auctions a"
                    "  ON LOWER(t.auction_address) = LOWER(a.auction_address) AND t.chain_id = a.chain_id"
                    f" WHERE 1=1{chain_filter_sql}{time_filter})"
                )

            query = text(f"""
                SELECT 
                    {auctions_count_sql} as total_auctions,
                    {active_auctions_sql} as active_auctions,
                    {tokens_count_sql} as unique_tokens,
                    {rounds_count_sql} as total_rounds,
                    {takes_count_sql} as total_takes,
                    {participants_count_sql} as total_participants,
                    {volume_usd_sql} as total_volume_usd
            """)

            result = await db.execute(query, params)
            return result.fetchone()

        except Exception as e:
            logger.warning(f"Error querying system stats, returning zeros: {e}")
            from collections import namedtuple
            StatsResult = namedtuple('StatsResult', ['total_auctions', 'active_auctions', 'unique_tokens', 'total_rounds', 'total_takes', 'total_participants', 'total_volume_usd'])
            return StatsResult(0, 0, 0, 0, 0, 0, 0.0)
    
    @staticmethod
    async def get_recent_takes_activity(db: AsyncSession, limit: int = 25, chain_id: int = None):
        """Get recent takes activity across all Auctions"""
        chain_filter = "WHERE als.chain_id = :chain_id" if chain_id else ""
        
        query = text(f"""
            SELECT 
                als.take_id as id,
                'take' as event_type,
                als.auction_address,
                als.chain_id,
                als.from_token,
                als.to_token,
                als.amount_taken as amount,
                als.price,
                als.taker as participant,
                EXTRACT(EPOCH FROM als.timestamp)::INTEGER as timestamp,
                als.transaction_hash as tx_hash,
                als.block_number,
                als.round_id,
                als.take_seq
            FROM takes als
            {chain_filter}
            ORDER BY als.timestamp DESC
            LIMIT :limit
        """)
        
        params = {"limit": limit}
        if chain_id:
            params["chain_id"] = chain_id
            
        result = await db.execute(query, params)
        return result.fetchall()

    @staticmethod
    async def get_recent_takes(db: AsyncSession, limit: int = 100, chain_id: int = None):
        """Get recent takes across all auctions from enriched view"""
        enriched = await DatabaseQueries._get_enriched_takes_relation(db)
        chain_filter = "WHERE chain_id = :chain_id" if chain_id else ""
        query = text(f"""
            SELECT 
                take_id,
                auction_address,
                chain_id,
                round_id,
                take_seq,
                taker,
                from_token,
                to_token,
                amount_taken,
                amount_paid,
                price,
                timestamp,
                seconds_from_round_start,
                block_number,
                transaction_hash,
                log_index,
                round_kicked_at,
                from_token_symbol,
                from_token_name,
                from_token_decimals,
                to_token_symbol,
                to_token_name,
                to_token_decimals,
                from_token_price_usd,
                to_token_price_usd as want_token_price_usd,
                amount_taken_usd,
                amount_paid_usd,
                price_differential_usd,
                price_differential_percent
            FROM {enriched}
            {chain_filter}
            ORDER BY timestamp DESC
            LIMIT :limit
        """)
        params = {"limit": limit}
        if chain_id:
            params["chain_id"] = chain_id
        result = await db.execute(query, params)
        return result.fetchall()

    @staticmethod
    async def get_takers_summary(db: AsyncSession, sort_by: str, limit: int, page: int, chain_id: Optional[int], skip_count: bool = False):
        """Get ranked takers with summary statistics using materialized view"""
        order_clause = {
            "volume": "total_volume_usd DESC NULLS LAST",
            "takes": "total_takes DESC",
            "recent": "last_take DESC NULLS LAST"
        }.get(sort_by, "total_volume_usd DESC NULLS LAST")
        # Prefer MV when present; fallback to dynamic view
        summary_relation = await DatabaseQueries._get_takers_summary_relation(db)
        chain_filter = ""
        if chain_id:
            # Both MV and VW expose active_chains int[]; use it when available
            chain_filter = f"WHERE {chain_id} = ANY(active_chains)"

        offset = (page - 1) * limit
        takers: list[dict] = []
        total: Optional[int] = None

        # Try dynamic view first
        try:
            query = text(f"""
                SELECT 
                    taker,
                    total_takes,
                    unique_auctions,
                    unique_chains,
                    total_volume_usd,
                    avg_take_size_usd,
                    first_take,
                    last_take,
                    active_chains,
                    ROW_NUMBER() OVER (ORDER BY total_takes DESC) as rank_by_takes,
                    ROW_NUMBER() OVER (ORDER BY total_volume_usd DESC NULLS LAST) as rank_by_volume,
                    total_profit_usd,
                    success_rate_percent,
                    takes_last_7d,
                    takes_last_30d,
                    volume_last_7d,
                    volume_last_30d
                FROM {summary_relation}
                {chain_filter}
                ORDER BY {order_clause}
                LIMIT :limit OFFSET :offset
            """)
            result = await db.execute(query, {"limit": limit, "offset": offset})
            takers = [dict(row._mapping) for row in result.fetchall()]
            if not skip_count:
                count_query = text(f"SELECT COUNT(*) FROM {summary_relation} {chain_filter}")
                total = (await db.execute(count_query)).scalar()
        except Exception as e:
            # Rollback on failure before computing fallback
            try:
                await db.rollback()
            except Exception:
                pass
            logger.warning(f"Primary takers summary view failed; falling back to compute: {e}")
            takers = []
            total = 0

        # Fallback: If MV exists but is empty (or unavailable), compute on-the-fly from enriched view
        if not takers and (skip_count or not total or total == 0):
            enriched = await DatabaseQueries._get_enriched_takes_relation(db)
            fallback_cte = f"""
                WITH taker_base AS (
                    SELECT 
                        LOWER(t.taker) AS taker,
                        COUNT(*) AS total_takes,
                        COUNT(DISTINCT t.auction_address) AS unique_auctions,
                        COUNT(DISTINCT t.chain_id) AS unique_chains,
                        COALESCE(SUM(t.amount_taken_usd), 0) AS total_volume_usd,
                        AVG(t.amount_taken_usd) AS avg_take_size_usd,
                        COALESCE(SUM(t.price_differential_usd), 0) AS total_profit_usd,
                        AVG(t.price_differential_usd) AS avg_profit_per_take_usd,
                        MIN(t.timestamp) AS first_take,
                        MAX(t.timestamp) AS last_take,
                        ARRAY_AGG(DISTINCT t.chain_id ORDER BY t.chain_id) AS active_chains,
                        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days') AS takes_last_7d,
                        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days') AS takes_last_30d,
                        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days'), 0) AS volume_last_7d,
                        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days'), 0) AS volume_last_30d,
                        COUNT(*) FILTER (WHERE t.price_differential_usd > 0) AS profitable_takes,
                        COUNT(*) FILTER (WHERE t.price_differential_usd < 0) AS unprofitable_takes
                    FROM {enriched} t
                    WHERE t.taker IS NOT NULL
                    {('AND t.chain_id = :chain_id') if chain_id else ''}
                    GROUP BY LOWER(t.taker)
                ), ranked AS (
                    SELECT 
                        *,
                        RANK() OVER (ORDER BY total_takes DESC) AS rank_by_takes,
                        RANK() OVER (ORDER BY total_volume_usd DESC NULLS LAST) AS rank_by_volume,
                        RANK() OVER (ORDER BY total_profit_usd DESC NULLS LAST) AS rank_by_profit,
                        CASE WHEN (profitable_takes + unprofitable_takes) > 0
                             THEN profitable_takes::DECIMAL / (profitable_takes + unprofitable_takes) * 100
                             ELSE NULL END AS success_rate_percent
                    FROM taker_base
                )
            """

            # Total from fallback
            fb_total_query = text(f"""
                {fallback_cte}
                SELECT COUNT(*) FROM ranked
            """)
            fb_params = {}
            if chain_id:
                fb_params["chain_id"] = chain_id
            if not skip_count:
                total = (await db.execute(fb_total_query, fb_params)).scalar() or 0

            # Page from fallback
            fb_query = text(f"""
                {fallback_cte}
                SELECT 
                    taker,
                    total_takes,
                    unique_auctions,
                    unique_chains,
                    total_volume_usd,
                    avg_take_size_usd,
                    first_take,
                    last_take,
                    active_chains,
                    rank_by_takes,
                    rank_by_volume,
                    total_profit_usd,
                    success_rate_percent,
                    takes_last_7d,
                    takes_last_30d,
                    volume_last_7d,
                    volume_last_30d
                FROM ranked
                ORDER BY {order_clause}
                LIMIT :limit OFFSET :offset
            """)
            fb_params.update({"limit": limit, "offset": offset})
            fb_result = await db.execute(fb_query, fb_params)
            takers = [dict(row._mapping) for row in fb_result.fetchall()]

        has_next = False
        if skip_count:
            has_next = len(takers) == limit
        else:
            has_next = (page * limit) < (total or 0)

        return {
            "takers": takers,
            "total": (total or 0) if not skip_count else None,
            "page": page,
            "per_page": limit,
            "has_next": has_next
        }

    @staticmethod
    async def get_taker_details(db: AsyncSession, taker_address: str):
        """Get comprehensive taker details using materialized view"""
        # Get taker data from MV if present; fallback to dynamic view (ranks computed below when missing)
        summary_relation = await DatabaseQueries._get_takers_summary_relation(db)
        query = text(f"""
            SELECT 
                taker,
                total_takes,
                unique_auctions,
                unique_chains,
                total_volume_usd,
                avg_take_size_usd,
                first_take,
                last_take,
                active_chains
            FROM {summary_relation}
            WHERE LOWER(taker) = LOWER(:taker)
        """)
        
        try:
            result = await db.execute(query, {"taker": taker_address})
            taker_data = result.fetchone()
        except Exception as e:
            # Ensure we rollback the failed transaction before attempting fallback queries
            try:
                await db.rollback()
            except Exception:
                pass
            logger.error(f"Taker details primary view failed; falling back to on-the-fly computation: {e}")
            taker_data = None
        
        # If we have data but it lacks ranks, compute them
        if taker_data:
            data = dict(taker_data._mapping)
            needs_ranks = ('rank_by_takes' not in data) or ('rank_by_volume' not in data) or (data.get('rank_by_takes') is None and data.get('rank_by_volume') is None)
            try:
                enriched = await DatabaseQueries._get_enriched_takes_relation(db)
                ranks_q = text(f"""
                    WITH base AS (
                        SELECT LOWER(t.taker) AS taker,
                               COUNT(*) AS total_takes,
                               COALESCE(SUM(t.amount_taken_usd), 0) AS total_volume_usd
                        FROM {enriched} t
                        WHERE t.taker IS NOT NULL
                        GROUP BY LOWER(t.taker)
                    ), ranked AS (
                        SELECT taker,
                               total_takes,
                               total_volume_usd,
                               RANK() OVER (ORDER BY total_takes DESC) AS rank_by_takes,
                               RANK() OVER (ORDER BY total_volume_usd DESC NULLS LAST) AS rank_by_volume
                        FROM base
                    )
                    SELECT r.rank_by_takes, r.rank_by_volume, (SELECT COUNT(*) FROM base) AS total_takers
                    FROM ranked r WHERE r.taker = LOWER(:taker)
                """)
                rk = await db.execute(ranks_q, {"taker": taker_address})
                row = rk.fetchone()
                if row:
                    data['rank_by_takes'] = row.rank_by_takes
                    data['rank_by_volume'] = row.rank_by_volume
                    data['total_takers'] = int(row.total_takers or 0)
                taker_data = type('Row', (), {'_mapping': data})  # minimal row-like wrapper
            except Exception:
                pass

        if not taker_data:
            enriched = await DatabaseQueries._get_enriched_takes_relation(db)
            # Fallback: compute directly from vw_takes_enriched if MV empty/not populated
            fb_query = text(f"""
                WITH base_all AS (
                    SELECT 
                        LOWER(t.taker) AS taker,
                        COUNT(*) AS total_takes,
                        COUNT(DISTINCT t.auction_address) AS unique_auctions,
                        COUNT(DISTINCT t.chain_id) AS unique_chains,
                        COALESCE(SUM(t.amount_taken_usd), 0) AS total_volume_usd,
                        AVG(t.amount_taken_usd) AS avg_take_size_usd,
                        MIN(t.timestamp) AS first_take,
                        MAX(t.timestamp) AS last_take,
                        ARRAY_AGG(DISTINCT t.chain_id ORDER BY t.chain_id) AS active_chains,
                        COALESCE(SUM(t.price_differential_usd), 0) AS total_profit_usd,
                        AVG(t.price_differential_usd) AS avg_profit_per_take_usd,
                        COUNT(*) FILTER (WHERE t.price_differential_usd > 0) AS profitable_takes,
                        COUNT(*) FILTER (WHERE t.price_differential_usd < 0) AS unprofitable_takes,
                        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days') AS takes_last_7d,
                        COUNT(*) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days') AS takes_last_30d,
                        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '7 days'), 0) AS volume_last_7d,
                        COALESCE(SUM(t.amount_taken_usd) FILTER (WHERE t.timestamp >= NOW() - INTERVAL '30 days'), 0) AS volume_last_30d
                    FROM {enriched} t
                    WHERE t.taker IS NOT NULL
                    GROUP BY LOWER(t.taker)
                ), ranked AS (
                    SELECT taker,
                           RANK() OVER (ORDER BY total_takes DESC) AS rank_by_takes,
                           RANK() OVER (ORDER BY total_volume_usd DESC NULLS LAST) AS rank_by_volume
                    FROM base_all
                ), one AS (
                    SELECT * FROM base_all WHERE taker = LOWER(:taker)
                )
                SELECT 
                    o.taker,
                    o.total_takes,
                    o.unique_auctions,
                    o.unique_chains,
                    o.total_volume_usd,
                    o.avg_take_size_usd,
                    o.first_take,
                    o.last_take,
                    o.active_chains,
                    r.rank_by_takes,
                    r.rank_by_volume,
                    o.total_profit_usd,
                    o.avg_profit_per_take_usd,
                    CASE WHEN (o.profitable_takes + o.unprofitable_takes) > 0
                         THEN o.profitable_takes::DECIMAL / (o.profitable_takes + o.unprofitable_takes) * 100
                         ELSE NULL END AS success_rate_percent,
                    o.takes_last_7d,
                    o.takes_last_30d,
                    o.volume_last_7d,
                    o.volume_last_30d,
                    o.profitable_takes,
                    o.unprofitable_takes,
                    (SELECT COUNT(*) FROM base_all) AS total_takers
                FROM one o
                LEFT JOIN ranked r ON r.taker = o.taker
            """)
            fb_res = await db.execute(fb_query, {"taker": taker_address})
            taker_data = fb_res.fetchone()
            if not taker_data:
                from fastapi import HTTPException
                raise HTTPException(status_code=404, detail="Taker not found")
        
        # Get auction breakdown using enriched view
        auction_breakdown_query = text("""
            SELECT 
                auction_address,
                chain_id,
                COUNT(*) as takes_count,
                SUM(amount_taken_usd) as volume_usd,
                MIN(timestamp) as first_take,
                MAX(timestamp) as last_take
            FROM vw_takes_enriched
            WHERE LOWER(taker) = LOWER(:taker)
            GROUP BY auction_address, chain_id
            ORDER BY volume_usd DESC NULLS LAST
        """)
        
        breakdown_result = await db.execute(auction_breakdown_query, {"taker": taker_address})
        auction_breakdown = [dict(row._mapping) for row in breakdown_result.fetchall()]
        
        return {
            **dict(taker_data._mapping),
            "auction_breakdown": auction_breakdown
        }

    @staticmethod
    async def get_taker_takes(db: AsyncSession, taker_address: str, limit: int, page: int):
        """Get paginated takes for a taker using enriched view"""
        offset = (page - 1) * limit
        enriched = await DatabaseQueries._get_enriched_takes_relation(db)
        query = text(f"""
            SELECT 
                take_id,
                auction_address,
                chain_id,
                round_id,
                take_seq,
                taker,
                from_token,
                to_token,
                amount_taken,
                amount_paid,
                price,
                timestamp,
                seconds_from_round_start,
                block_number,
                transaction_hash as tx_hash,
                log_index,
                amount_taken_usd,
                amount_paid_usd,
                amount_taken_usd as price_usd,  -- For backwards compatibility
                price_differential_usd,
                price_differential_percent,
                from_token_symbol,
                from_token_name,
                from_token_decimals,
                to_token_symbol,
                to_token_name,
                to_token_decimals
            FROM {enriched}
            WHERE LOWER(taker) = LOWER(:taker)
            ORDER BY timestamp DESC
            LIMIT :limit OFFSET :offset
        """)
        
        result = await db.execute(query, {"taker": taker_address, "limit": limit, "offset": offset})
        takes = [dict(row._mapping) for row in result.fetchall()]
        
        # Get total count
        count_result = await db.execute(
            text("SELECT COUNT(*) FROM takes WHERE LOWER(taker) = LOWER(:taker)"),
            {"taker": taker_address}
        )
        total = int(count_result.scalar() or 0)
        total_pages = (total + limit - 1) // limit if total > 0 else 1

        return {
            "takes": takes,
            # Keep legacy keys
            "total": total,
            "per_page": limit,
            "has_next": (page * limit) < total,
            # Also provide UI-expected keys
            "total_count": total,
            "limit": limit,
            "page": page,
            "total_pages": total_pages,
        }

    @staticmethod
    async def get_taker_token_pairs(db: AsyncSession, taker_address: str, page: int = 1, limit: int = 50):
        """Get most frequented token pairs for a taker with pagination"""
        offset = (page - 1) * limit
        
        # Main query with USD calculations using token_prices (no dependency on amount_taken_usd column)
        query = text("""
            WITH token_pair_summary AS (
                SELECT 
                    t.from_token,
                    t.to_token,
                    COUNT(*) as takes_count,
                    -- Volume in USD computed from token_prices at or before the take's block
                    COALESCE(SUM(CASE 
                        WHEN tp_from.price_usd IS NOT NULL THEN CAST(t.amount_taken AS DECIMAL) * tp_from.price_usd 
                        ELSE NULL END), 0) as volume_usd,
                    MAX(t.timestamp) as last_take_at,
                    MIN(t.timestamp) as first_take_at,
                    COUNT(DISTINCT t.auction_address) as unique_auctions,
                    COUNT(DISTINCT t.chain_id) as unique_chains,
                    ARRAY_AGG(DISTINCT t.chain_id ORDER BY t.chain_id) as active_chains
                FROM takes t
                -- Join with token_prices for from_token (closest block <= take block)
                LEFT JOIN LATERAL (
                    SELECT price_usd 
                    FROM token_prices 
                    WHERE chain_id = t.chain_id 
                    AND LOWER(token_address) = LOWER(t.from_token)
                    AND block_number <= t.block_number
                    ORDER BY block_number DESC
                    LIMIT 1
                ) tp_from ON true
                WHERE LOWER(t.taker) = LOWER(:taker)
                GROUP BY t.from_token, t.to_token
            )
            SELECT 
                tps.*,
                tok1.symbol as from_token_symbol,
                tok1.name as from_token_name,
                tok1.decimals as from_token_decimals,
                tok2.symbol as to_token_symbol,
                tok2.name as to_token_name,
                tok2.decimals as to_token_decimals
            FROM token_pair_summary tps
            LEFT JOIN tokens tok1 ON tps.from_token = tok1.address
            LEFT JOIN tokens tok2 ON tps.to_token = tok2.address
            ORDER BY takes_count DESC, volume_usd DESC NULLS LAST
            LIMIT :limit OFFSET :offset
        """)
        
        # Count query for pagination
        count_query = text("""
            SELECT COUNT(DISTINCT t.from_token || '::' || t.to_token) as total_count
            FROM takes t
            WHERE LOWER(t.taker) = LOWER(:taker)
        """)
        
        # Execute both queries
        result = await db.execute(query, {"taker": taker_address, "limit": limit, "offset": offset})
        token_pairs = [dict(row._mapping) for row in result.fetchall()]
        
        count_result = await db.execute(count_query, {"taker": taker_address})
        total_count = count_result.scalar() or 0
        
        total_pages = (total_count + limit - 1) // limit
        
        return {
            "token_pairs": token_pairs,
            "page": page,
            "per_page": limit,
            "total_count": total_count,
            "total_pages": total_pages,
            "has_next": page < total_pages,
            "has_prev": page > 1
        }

    @staticmethod
    async def get_take_details(db: AsyncSession, auction_address: str, round_id: int, take_seq: int, chain_id: int):
        """Get simplified take details without complex price analysis"""
        try:
            
            # Get the take details from enriched view
            enriched = await DatabaseQueries._get_enriched_takes_relation(db)
            take_query = text(f"""
                SELECT 
                    t.*,
                    tf.symbol as from_token_symbol,
                    tt.symbol as to_token_symbol,
                    a.decay_rate as auction_decay_rate,
                    a.update_interval as auction_update_interval
                FROM {enriched} t
                LEFT JOIN tokens tf ON LOWER(tf.address) = LOWER(t.from_token) 
                                   AND tf.chain_id = t.chain_id
                LEFT JOIN tokens tt ON LOWER(tt.address) = LOWER(t.to_token) 
                                   AND tt.chain_id = t.chain_id
                LEFT JOIN auctions a ON LOWER(a.auction_address) = LOWER(t.auction_address) 
                                    AND a.chain_id = t.chain_id
                WHERE t.chain_id = :chain_id 
                  AND LOWER(t.auction_address) = LOWER(:auction_address)
                  AND t.round_id = :round_id 
                  AND t.take_seq = :take_seq
                LIMIT 1
            """)
            
            result = await db.execute(take_query, {
                "chain_id": chain_id,
                "auction_address": auction_address,
                "round_id": round_id,
                "take_seq": take_seq
            })
            take_row = result.fetchone()
            
            if not take_row:
                return None
            
            # Skip round context for now to isolate the error
            context_row = None
            
            return {
                "take_data": take_row,
                "price_quotes": [],  # Empty for now since token_prices table doesn't exist
                "round_context": context_row
            }
            
        except Exception as e:
            logger.error(f"Database error getting take details: {e}")
            raise


# Initialize database connection check
async def init_database():
    """Initialize database connection and verify setup"""
    logger.info("Checking database connection...")
    
    if await check_database_connection():
        logger.info("✅ Database connection successful")
        
        logger.info("📊 Database connection verified")
        
        return True
    else:
        logger.error("❌ Database connection failed")
        return False

# ========================================
# Data Provider Interfaces (consolidated from data_service.py)
# ========================================

from abc import ABC, abstractmethod
from typing import List, Optional, Dict, Any

try:
    from monitoring.api.models.auction import (
        AuctionResponse,
        AuctionRoundInfo,
        AuctionActivity,
        AuctionParameters,
        TokenInfo,
        SystemStats,
        Take,
        TakeMessage,
        AuctionListResponse,
        AuctionListItem
    )
except ImportError:
    # When running from within the api directory
    from monitoring.api.models.auction import (
        AuctionResponse,
        AuctionRoundInfo,
        AuctionActivity,
        AuctionParameters,
        TokenInfo,
        SystemStats,
        Take,
        TakeMessage,
        AuctionListResponse,
        AuctionListItem
    )

# Import config functions
try:
    from monitoring.api.config import get_settings, is_mock_mode, is_development_mode
except ImportError:
    # Handle imports for when running standalone
    pass


class DataProvider(ABC):
    """Abstract base class for data providers"""
    
    @abstractmethod
    async def get_auctions(
        self, 
        status: str = "all", 
        page: int = 1, 
        limit: int = 20,
        chain_id: Optional[int] = None
    ) -> Dict[str, Any]:
        """Get paginated list of auctions"""
        pass
    
    @abstractmethod
    async def get_auction_details(self, auction_address: str, chain_id: int) -> 'AuctionResponse':
        """Get detailed auction information"""
        pass
    
    @abstractmethod
    async def get_auction_takes(
        self, 
        auction_address: str, 
        round_id: Optional[int] = None, 
        limit: int = 50,
        chain_id: int = None,
        offset: int = 0
    ) -> Dict[str, Any]:
        """Get takes for an auction with pagination info"""
        pass
    
    @abstractmethod
    async def get_auction_rounds(
        self, 
        auction_address: str, 
        from_token: str, 
        limit: int = 50,
        chain_id: int = None
    ) -> Dict[str, Any]:
        """Get round history for an auction"""
        pass
    
    @abstractmethod
    async def get_tokens(self) -> Dict[str, Any]:
        """Get all tokens"""
        pass
    
    @abstractmethod
    async def get_system_stats(self, chain_id: Optional[int] = None) -> 'SystemStats':
        """Get system statistics"""
        pass

    @abstractmethod
    async def get_recent_takes(
        self,
        limit: int = 100,
        chain_id: Optional[int] = None
    ) -> List['Take']:
        """Get recent takes across all auctions"""
        pass


class MockDataProvider(DataProvider):
    """Mock data provider for testing and development"""
    
    def __init__(self):
        self.mock_tokens = [
            TokenInfo(
                address="0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512", 
                symbol="USDC", 
                name="USD Coin", 
                decimals=6, 
                chain_id=31337
            ),
            TokenInfo(
                address="0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0", 
                symbol="USDT", 
                name="Tether USD", 
                decimals=6, 
                chain_id=31337
            ),
            TokenInfo(
                address="0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9", 
                symbol="WETH", 
                name="Wrapped Ether", 
                decimals=18, 
                chain_id=31337
            )
        ]
    
    async def get_auctions(self, status="all", page=1, limit=20, chain_id=None):
        # Simple mock response
        return {
            "auctions": [],
            "total": 0,
            "page": page,
            "per_page": limit,
            "has_next": False
        }

    async def get_auction_details(self, auction_address: str, chain_id: int) -> AuctionResponse:
        """Get mock auction details"""
        # Return simplified mock data
        current_round = AuctionRoundInfo(
            round_id=1,
            kicked_at=datetime.now() - timedelta(minutes=30),
            initial_available="1000000000000000000000",
            is_active=True,  # Mock data - would be calculated in real implementation
            current_price="950000",
            available_amount="800000000000000000000",
            time_remaining=1800,
            seconds_elapsed=1800,
            total_takes=5,
        )
        
        return AuctionResponse(
            address=auction_address,
            chain_id=chain_id,
            deployer="0x1234567890123456789012345678901234567890",
            governance="0x9876543210987654321098765432109876543210",
            from_tokens=self.mock_tokens[:2],
            want_token=self.mock_tokens[2],
            parameters=AuctionParameters(
                update_interval=60,
                step_decay="995000000000000000000000000",
                auction_length=3600,
                starting_price="1000000"
            ),
            current_round=current_round,
            activity=AuctionActivity(
                total_participants=10,
                total_volume="500000000",
                total_rounds=1,
                total_takes=5,
                recent_takes=[]
            ),
            deployed_at=datetime.now() - timedelta(days=30),
            last_kicked=datetime.now() - timedelta(minutes=30)
        )

    async def get_auction_takes(self, auction_address: str, round_id: Optional[int] = None, limit: int = 50, chain_id: int = None, offset: int = 0) -> Dict[str, Any]:
        """Generate mock takes data"""
        return {
            "takes": [],
            "total": 0,
            "page": max(1, (offset // limit) + 1),
            "per_page": limit,
            "total_pages": 0
        }

    async def get_auction_rounds(self, auction_address: str, from_token: str = None, limit: int = 50, chain_id: int = None, round_id: int = None) -> Dict[str, Any]:
        """Generate mock rounds data"""
        return {
            "auction": auction_address,
            "from_token": from_token,
            "rounds": [],
            "total": 0
        }

    async def get_tokens(self) -> Dict[str, Any]:
        """Return mock tokens"""
        return {
            "tokens": self.mock_tokens,
            "count": len(self.mock_tokens)
        }
    
    async def get_system_stats(self, chain_id: Optional[int] = None) -> SystemStats:
        """Return mock system stats"""
        return SystemStats(
            total_auctions=5,
            active_auctions=2,
            total_participants=50,
            total_takes=100,
            unique_tokens=10,
            total_rounds=15,
            total_volume_usd=1250000.50
        )

    async def get_recent_takes(self, limit: int = 100, chain_id: Optional[int] = None) -> List['Take']:
        # Return empty list in mock mode for now
        return []


class DatabaseDataProvider(DataProvider):
    """Database data provider using direct SQL queries"""
    
    def __init__(self):
        pass

    def _safe_get(self, row, key, default=None):
        """Safely get value from SQLAlchemy Row using mapping first, then attribute.

        This avoids NoSuchColumnError arising from attribute access on missing keys.
        """
        try:
            mapping = getattr(row, '_mapping', None)
            if mapping is not None:
                # Only use mapping to avoid attribute lookups that can raise
                return mapping.get(key, default)
        except Exception:
            pass
        # Fallback for plain dict-like rows
        try:
            return row.get(key, default)  # type: ignore[attr-defined]
        except Exception:
            return default

    def _format_timestamp(self, ts):
        """Simple timestamp formatter for auction data"""
        if ts is None:
            return None
        if isinstance(ts, (int, float)):
            return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
        if hasattr(ts, 'isoformat'):
            return ts.isoformat()
        return None

    def _calculate_time_values(self, round_start, round_end):
        """Calculate time remaining and seconds elapsed"""
        if not round_start:
            return None, 0
            
        now = datetime.now(timezone.utc)
        
        # Calculate seconds elapsed
        if hasattr(round_start, 'timestamp'):
            seconds_elapsed = int((now - round_start).total_seconds())
        elif isinstance(round_start, (int, float)):
            seconds_elapsed = int(now.timestamp() - round_start)
        else:
            seconds_elapsed = 0
            
        # Calculate time remaining
        time_remaining = None
        if round_end:
            if hasattr(round_end, 'timestamp'):
                time_remaining = max(0, int((round_end - now).total_seconds()))
            elif isinstance(round_end, (int, float)):
                time_remaining = max(0, int(round_end - now.timestamp()))
                
        return time_remaining, seconds_elapsed

    def _build_current_round(self, row):
        """Build current round dict from database row"""
        if not self._safe_get(row, 'current_round_id'):
            return None
            
        from_token = None
        if self._safe_get(row, 'current_round_from_token'):
            from_token = {
                "address": self._safe_get(row, 'current_round_from_token'),
                "symbol": self._safe_get(row, 'from_token_symbol') or f"{self._safe_get(row, 'current_round_from_token', '')[:6]}...",
                "name": self._safe_get(row, 'from_token_name') or "Unknown Token",
                "decimals": self._safe_get(row, 'from_token_decimals') or 18,
                "chain_id": self._safe_get(row, 'chain_id')
            }

        # Prefer explicit round_start/round_end if present; otherwise compute from last_kicked + auction_length
        round_start_val = self._safe_get(row, 'round_start') or self._safe_get(row, 'last_kicked_timestamp')
        round_end_val = self._safe_get(row, 'round_end')
        if round_end_val is None:
            al = self._safe_get(row, 'auction_length')
            if round_start_val is not None and al is not None:
                try:
                    if hasattr(round_start_val, 'timestamp'):
                        # datetime → datetime + seconds
                        from datetime import timedelta
                        round_end_val = round_start_val + timedelta(seconds=int(al))
                    elif isinstance(round_start_val, (int, float)):
                        round_end_val = (round_start_val + int(al))
                except Exception:
                    round_end_val = None
        time_remaining, seconds_elapsed = self._calculate_time_values(round_start_val, round_end_val)
        
        round_start_ts = None
        _rs = round_start_val
        if _rs:
            if hasattr(_rs, 'timestamp'):
                round_start_ts = int(_rs.timestamp())
            elif isinstance(_rs, (int, float)):
                round_start_ts = int(_rs)
                
        round_end_ts = None
        _re = round_end_val
        if _re:
            if hasattr(_re, 'timestamp'):
                round_end_ts = int(_re.timestamp())
            elif isinstance(_re, (int, float)):
                round_end_ts = int(_re)

        round_info = {
            "round_id": self._safe_get(row, 'current_round_id'),
            "kicked_at": self._format_timestamp(self._safe_get(row, 'last_kicked_timestamp')),
            "round_start": round_start_ts,
            "round_end": round_end_ts,
            "initial_available": str(self._safe_get(row, 'initial_available') or 0),
            "available_amount": str(self._safe_get(row, 'current_available') or 0),
            "is_active": bool(self._safe_get(row, 'has_active_round')), 
            "total_takes": self._safe_get(row, 'current_round_takes') or 0,
            "time_remaining": time_remaining,
            "seconds_elapsed": seconds_elapsed,
            "from_token": from_token,
            "transaction_hash": self._safe_get(row, 'current_round_transaction_hash'),
            "block_number": self._safe_get(row, 'current_round_block_number'),
            "from_token_price_usd": (
                str(self._safe_get(row, 'from_token_price_usd'))
                if self._safe_get(row, 'from_token_price_usd') is not None else None
            ),
            "want_token_price_usd": (
                str(self._safe_get(row, 'want_token_price_usd'))
                if self._safe_get(row, 'want_token_price_usd') is not None else None
            )
        }
        try:
            if round_info.get("from_token_price_usd") or round_info.get("want_token_price_usd"):
                logger.info(
                    f"Round prices for {self._safe_get(row, 'auction_address')}: block={round_info.get('block_number')} from={round_info.get('from_token_price_usd')} want={round_info.get('want_token_price_usd')}"
                )
        except Exception:
            pass
        return round_info

    async def _get_bulk_enabled_tokens(self, session, rows):
        """Get enabled tokens for all auctions in one optimized pass"""
        if not rows:
            return {}
            
        # Group by chain_id for efficient bulk queries
        from collections import defaultdict
        addrs_by_chain = defaultdict(list)
        for row in rows:
            chain_id = self._safe_get(row, 'chain_id')
            address = (self._safe_get(row, 'auction_address') or '').lower()
            addrs_by_chain[chain_id].append(address)
        
        # Build flat tokens mapping: "chain_id:auction_address" -> [tokens]
        tokens_map = {}
        for chain_id, addresses in addrs_by_chain.items():
            token_rows = await DatabaseQueries.get_enabled_tokens_for_addresses(session, chain_id, addresses)
            for token_row in token_rows:
                key = f"{chain_id}:{token_row['auction_address'].lower()}"
                if key not in tokens_map:
                    tokens_map[key] = []
                tokens_map[key].append({
                    "address": token_row['token_address'],
                    "symbol": token_row['token_symbol'] or "Unknown",
                    "name": token_row['token_name'] or "Unknown",
                    "decimals": token_row['token_decimals'] or 18,
                    "chain_id": token_row['chain_id']
                })
                
        return tokens_map

    async def get_auctions(self, status="all", page=1, limit=20, chain_id=None):
        """Optimized auctions retrieval with direct SQLAlchemy row access"""
        async with AsyncSessionLocal() as session:
            # Get data from database
            active_only = status == "active"
            offset = (page - 1) * limit
            
            rows = await DatabaseQueries.get_auctions(session, active_only, chain_id, limit=limit, offset=offset)
            total_count = await DatabaseQueries.count_auctions(session, active_only, chain_id)
            
            if not rows:
                return {
                    "auctions": [],
                    "total": total_count,
                    "page": page,
                    "per_page": limit,
                    "has_next": False
                }
            
            # Get all enabled tokens in one optimized pass
            tokens_map = await self._get_bulk_enabled_tokens(session, rows)
            
            # Build auctions directly from database rows - single pass, no conversions
            auctions = []
            for row in rows:
                # Get enabled tokens for this auction
                auction_key = f"{self._safe_get(row, 'chain_id')}:{(self._safe_get(row, 'auction_address') or '').lower()}"
                from_tokens = tokens_map.get(auction_key, [])
                
                # Build auction object with direct attribute access
                auction = {
                    "address": self._safe_get(row, 'auction_address'),
                    "chain_id": self._safe_get(row, 'chain_id'),
                    "from_tokens": from_tokens,
                    "want_token": {
                        "address": self._safe_get(row, 'want_token') or "Unknown",
                        "symbol": self._safe_get(row, 'want_token_symbol') or "Unknown",
                        "name": self._safe_get(row, 'want_token_name') or "Unknown Token",
                        "decimals": self._safe_get(row, 'want_token_decimals') or 18,
                        "chain_id": self._safe_get(row, 'chain_id')
                    },
                    "current_round": self._build_current_round(row),
                    "last_kicked": self._format_timestamp(self._safe_get(row, 'last_kicked')),
                    "decay_rate": float(self._safe_get(row, 'decay_rate') or 0.0),
                    "update_interval": self._safe_get(row, 'update_interval'),
                    "has_active_round": bool(self._safe_get(row, 'has_active_round'))
                }
                auctions.append(auction)
            
            logger.info(f"Loaded {len(auctions)} auctions (total={total_count}) from database")
            
            # Return directly - FastAPI handles JSON serialization automatically
            return {
                "auctions": auctions,
                "total": total_count,
                "page": page,
                "per_page": limit,
                "has_next": (page * limit) < total_count,
                # normalized pagination keys
                "total_count": total_count,
                "total_pages": (total_count + limit - 1) // limit if total_count > 0 else 1,
                "limit": limit
            }

    async def get_tokens(self) -> Dict[str, Any]:
        """Get tokens from database"""
        try:
            async with AsyncSessionLocal() as session:
                tokens_data = await DatabaseQueries.get_all_tokens(session)
                tokens = []
                for token_row in tokens_data:
                    token = TokenInfo(
                        address=token_row.address,
                        symbol=token_row.symbol,
                        name=token_row.name,
                        decimals=token_row.decimals,
                        chain_id=token_row.chain_id
                    )
                    tokens.append(token)
                
                return {
                    "tokens": tokens,
                    "count": len(tokens)
                }
        except Exception as e:
            logger.error(f"Database error in get_tokens: {e}")
            raise Exception(f"Failed to fetch tokens from database: {e}")

    async def get_auction_details(self, auction_address: str, chain_id: int) -> AuctionResponse:
        """Get auction details from database"""
        async with AsyncSessionLocal() as session:
            logger.info(f"Querying auction details for {auction_address} on chain {chain_id}")
            
            # Get auction details from database
            auction_data = await DatabaseQueries.get_auction_details(session, auction_address, chain_id)
            
            if not auction_data:
                raise Exception(f"Auction {auction_address} not found in database")

            # Use actual database data from vw_auctions
            want_token = TokenInfo(
                    address=auction_data.want_token,
                    symbol=auction_data.want_token_symbol if hasattr(auction_data, 'want_token_symbol') else "Unknown",
                    name=getattr(auction_data, 'want_token_name', None) or "Unknown", 
                    decimals=getattr(auction_data, 'want_token_decimals', None) or 18,
                    chain_id=chain_id
                )

            parameters = AuctionParameters(
                update_interval=int(getattr(auction_data, 'update_interval', 60) or 60),
                step_decay=None,
                step_decay_rate=str(getattr(auction_data, 'step_decay_rate')) if getattr(auction_data, 'step_decay_rate', None) is not None else None,
                decay_rate=float(getattr(auction_data, 'decay_rate')) if getattr(auction_data, 'decay_rate', None) is not None else None,
                auction_length=int(getattr(auction_data, 'auction_length', 0) or 0),
                starting_price=str(getattr(auction_data, 'starting_price')) if getattr(auction_data, 'starting_price', None) is not None else "0"
            )
            
            current_round = None
            if getattr(auction_data, 'has_active_round', False) and getattr(auction_data, 'current_round_id', None):
                # Compose from_token object when available from JOIN
                from_token_obj = None
                if getattr(auction_data, 'current_round_from_token', None):
                    from_token_obj = TokenInfo(
                        address=str(getattr(auction_data, 'current_round_from_token')),
                        symbol=str(getattr(auction_data, 'from_token_symbol', None) or str(getattr(auction_data, 'current_round_from_token'))[:6] + "..."),
                        name=str(getattr(auction_data, 'from_token_name', None) or "Unknown Token"),
                        decimals=int(getattr(auction_data, 'from_token_decimals', None) or 18),
                        chain_id=chain_id
                    )

                # Time calculations
                now = datetime.now(timezone.utc)
                round_start_dt = getattr(auction_data, 'round_start', None)
                round_end_dt = getattr(auction_data, 'round_end', None)
                seconds_elapsed = 0
                time_remaining = None
                if round_start_dt is not None:
                    try:
                        seconds_elapsed = int((now - round_start_dt).total_seconds())
                    except Exception:
                        seconds_elapsed = 0
                if round_end_dt is not None:
                    try:
                        time_remaining = max(0, int((round_end_dt - now).total_seconds()))
                    except Exception:
                        time_remaining = None

                current_round = AuctionRoundInfo(
                    round_id=getattr(auction_data, 'current_round_id'),
                    kicked_at=datetime.fromtimestamp(getattr(auction_data, 'last_kicked')) if getattr(auction_data, 'last_kicked', None) else datetime.now(timezone.utc),
                    round_start=int(round_start_dt.timestamp()) if getattr(auction_data, 'round_start', None) is not None else None,
                    round_end=int(round_end_dt.timestamp()) if getattr(auction_data, 'round_end', None) is not None else None,
                    initial_available=str(getattr(auction_data, 'initial_available', 0) or 0),
                    is_active=getattr(auction_data, 'has_active_round', False),
                    available_amount=str(getattr(auction_data, 'current_available', 0) or 0),
                    time_remaining=time_remaining,
                    seconds_elapsed=seconds_elapsed,
                    total_takes=getattr(auction_data, 'current_round_takes', 0) or 0,
                    from_token=from_token_obj,
                    transaction_hash=str(getattr(auction_data, 'current_round_transaction_hash')) if getattr(auction_data, 'current_round_transaction_hash', None) else None
                )
                # Attach price info and block number when available
                try:
                    setattr(current_round, 'block_number', getattr(auction_data, 'current_round_block_number', None))
                    fpu = getattr(auction_data, 'from_token_price_usd', None)
                    wpu = getattr(auction_data, 'want_token_price_usd', None)
                    if fpu is not None:
                        setattr(current_round, 'from_token_price_usd', str(fpu))
                    if wpu is not None:
                        setattr(current_round, 'want_token_price_usd', str(wpu))
                except Exception:
                    pass

            # Get enabled tokens for this auction (detailed TokenInfo objects)
            enabled_tokens_data = await DatabaseQueries.get_enabled_tokens(session, auction_address, chain_id)
            from_tokens = []
            for t in (enabled_tokens_data or []):
                try:
                    from_tokens.append(TokenInfo(
                        address=str(t['token_address']),
                        symbol=t.get('token_symbol') or "Unknown",
                        name=t.get('token_name') or "Unknown",
                        decimals=int(t.get('token_decimals') or 18),
                        chain_id=int(t.get('chain_id') or chain_id)
                    ))
                except Exception:
                    continue

            # Get activity statistics for this auction
            activity_stats = await DatabaseQueries.get_auction_activity_stats(session, auction_address, chain_id)
            total_participants = activity_stats.total_participants if activity_stats else 0
            total_volume = str(activity_stats.total_volume) if activity_stats else "0"
            total_rounds = activity_stats.total_rounds if activity_stats else 0
            total_takes = activity_stats.total_takes if activity_stats else 0
            
            response = AuctionResponse(
                address=auction_address,
                chain_id=chain_id,
                deployer=auction_data.deployer or "0x0000000000000000000000000000000000000000",
                governance=getattr(auction_data, 'governance', None),
                from_tokens=from_tokens,
                want_token=want_token,
                parameters=parameters,
                current_round=current_round,
                activity=AuctionActivity(
                    total_participants=total_participants,
                    total_volume=total_volume,
                    total_rounds=total_rounds,
                    total_takes=total_takes,
                    recent_takes=[]  # Could be fetched if needed
                ),
                deployed_at=datetime.fromtimestamp(getattr(auction_data, 'deployed_timestamp', 0), tz=timezone.utc) if getattr(auction_data, 'deployed_timestamp', None) else datetime.now(tz=timezone.utc),
                last_kicked=datetime.fromtimestamp(getattr(auction_data, 'last_kicked')) if getattr(auction_data, 'last_kicked', None) else None
            )
            
            return response

    async def get_auction_takes(self, auction_address: str, round_id: Optional[int] = None, limit: int = 50, chain_id: int = None, offset: int = 0) -> Dict[str, Any]:
        """Get takes from database with pagination info"""
        async with AsyncSessionLocal() as session:
            # Get data from updated query that returns both takes and total count
            result = await DatabaseQueries.get_auction_takes(
                session, auction_address, round_id, chain_id, limit, offset
            )
            
            takes_data = result["takes"]
            total_count = result["total"]
            
            takes = []
            for take_row in takes_data:
                take = Take(
                    take_id=str(take_row.take_id) if take_row.take_id else f"take_{take_row.take_seq}",
                    auction=take_row.auction_address,
                    chain_id=take_row.chain_id,
                    round_id=take_row.round_id,
                    take_seq=take_row.take_seq,
                    taker=take_row.taker,
                    amount_taken=str(take_row.amount_taken),
                    amount_paid=str(take_row.amount_paid),
                    price=str(take_row.price),
                    timestamp=take_row.timestamp.isoformat() if hasattr(take_row.timestamp, 'isoformat') else str(take_row.timestamp),
                    tx_hash=take_row.transaction_hash,
                    block_number=take_row.block_number,
                    # Add token information
                    from_token=take_row.from_token,
                    to_token=take_row.to_token,
                    from_token_symbol=take_row.from_token_symbol if hasattr(take_row, 'from_token_symbol') else None,
                    from_token_name=take_row.from_token_name if hasattr(take_row, 'from_token_name') else None,
                    from_token_decimals=take_row.from_token_decimals if hasattr(take_row, 'from_token_decimals') else None,
                    to_token_symbol=take_row.to_token_symbol if hasattr(take_row, 'to_token_symbol') else None,
                    to_token_name=take_row.to_token_name if hasattr(take_row, 'to_token_name') else None,
                    to_token_decimals=take_row.to_token_decimals if hasattr(take_row, 'to_token_decimals') else None,
                    # Add USD price information
                    from_token_price_usd=str(take_row.from_token_price_usd) if getattr(take_row, 'from_token_price_usd', None) is not None else None,
                    want_token_price_usd=str(take_row.want_token_price_usd) if getattr(take_row, 'want_token_price_usd', None) is not None else None,
                    amount_taken_usd=str(take_row.amount_taken_usd) if getattr(take_row, 'amount_taken_usd', None) is not None else None,
                    amount_paid_usd=str(take_row.amount_paid_usd) if getattr(take_row, 'amount_paid_usd', None) is not None else None,
                    price_differential_usd=str(take_row.price_differential_usd) if getattr(take_row, 'price_differential_usd', None) is not None else None,
                    price_differential_percent=float(take_row.price_differential_percent) if getattr(take_row, 'price_differential_percent', None) is not None else None
                )
                takes.append(take)
            
            # Calculate pagination info
            current_page = max(1, (offset // limit) + 1)
            total_pages = (total_count + limit - 1) // limit if total_count > 0 else 1
            
            logger.info(f"Loaded {len(takes)} takes from database for {auction_address} (page {current_page}/{total_pages}, total: {total_count})")
            
            return {
                "takes": takes,
                "total": total_count,
                "page": current_page,
                "per_page": limit,
                "total_pages": total_pages,
                # normalized
                "total_count": total_count,
                "limit": limit,
                "has_next": current_page < total_pages
            }

    async def get_auction_rounds(self, auction_address: str, from_token: str = None, limit: int = 50, chain_id: int = None, round_id: int = None) -> Dict[str, Any]:
        """Get auction rounds from database using direct SQL query"""
        async with AsyncSessionLocal() as session:
            logger.info(f"Querying rounds for auction {auction_address}, from_token {from_token}, chain_id {chain_id}")
            
            # Use a direct SQL query to get the data with optional filters
            chain_filter = "AND ar.chain_id = :chain_id" if chain_id else ""
            token_filter = "AND LOWER(ar.from_token) = LOWER(:from_token)" if from_token else ""
            round_filter = "AND ar.round_id = :round_id" if round_id else ""
            
            query = text(f"""
                    SELECT 
                        ar.round_id,
                        ar.from_token,
                        ft.symbol as from_token_symbol,
                        ft.name as from_token_name,
                        ft.decimals as from_token_decimals,
                        ahp.want_token,
                        wt.symbol as want_token_symbol,
                        wt.name as want_token_name,
                        wt.decimals as want_token_decimals,
                        ar.kicked_at,
                        ar.initial_available,
                        ar.transaction_hash,
                        ar.round_start,
                        ar.round_end,
                        ((ar.kicked_at + 86400) > EXTRACT(EPOCH FROM NOW())::BIGINT 
                         AND (ar.initial_available - COALESCE(SUM(t.amount_taken), 0)) > 0) as is_active,
                        GREATEST(0, ((ar.kicked_at + 86400) - EXTRACT(EPOCH FROM NOW())::BIGINT))::INTEGER as time_remaining,
                        GREATEST(0, (EXTRACT(EPOCH FROM NOW())::BIGINT - ar.kicked_at))::INTEGER as seconds_elapsed,
                        COUNT(t.take_seq) as total_takes,
                        -- Add PnL aggregation from enriched view
                        COALESCE(SUM(vt.price_differential_usd), 0) as total_pnl_usd,
                        CASE 
                            WHEN COUNT(t.take_seq) > 0 THEN AVG(vt.price_differential_percent)
                            ELSE NULL 
                        END as avg_pnl_percent
                    FROM rounds ar
                JOIN auctions ahp 
                    ON LOWER(ar.auction_address) = LOWER(ahp.auction_address) 
                    AND ar.chain_id = ahp.chain_id
                LEFT JOIN tokens ft
                    ON LOWER(ar.from_token) = LOWER(ft.address)
                    AND ar.chain_id = ft.chain_id
                LEFT JOIN tokens wt
                    ON LOWER(ahp.want_token) = LOWER(wt.address)
                    AND ahp.chain_id = wt.chain_id
                LEFT JOIN takes t 
                    ON LOWER(ar.auction_address) = LOWER(t.auction_address)
                    AND ar.chain_id = t.chain_id 
                    AND ar.round_id = t.round_id
                LEFT JOIN vw_takes_enriched vt
                    ON LOWER(ar.auction_address) = LOWER(vt.auction_address)
                    AND ar.chain_id = vt.chain_id
                    AND ar.round_id = vt.round_id
                WHERE LOWER(ar.auction_address) = LOWER(:auction_address)
                    {chain_filter}
                    {token_filter}
                    {round_filter}
                    GROUP BY ar.round_id, ar.from_token, ft.symbol, ft.name, ft.decimals, ahp.want_token, wt.symbol, wt.name, wt.decimals, ar.kicked_at, ar.initial_available, ar.transaction_hash, ar.round_start, ar.round_end
                    ORDER BY ar.round_id DESC
                    LIMIT :limit
                """)
            
            params = {
                "auction_address": auction_address,
                "limit": limit
            }
            if chain_id:
                params["chain_id"] = chain_id
            if from_token:
                params["from_token"] = from_token
            if round_id:
                params["round_id"] = round_id
            
            result = await session.execute(query, params)
            rounds_data = result.fetchall()
            
            logger.info(f"Database returned {len(rounds_data)} rounds")
            
            rounds = []
            for round_row in rounds_data:
                # kicked_at is now a Unix timestamp (bigint) after migration
                kicked_at_iso = self._format_timestamp(round_row.kicked_at)
                
                round_info = {
                    "round_id": round_row.round_id,
                    "from_token": round_row.from_token,
                    "from_token_symbol": round_row.from_token_symbol if hasattr(round_row, 'from_token_symbol') else None,
                    "from_token_name": round_row.from_token_name if hasattr(round_row, 'from_token_name') else None,
                    "from_token_decimals": round_row.from_token_decimals if hasattr(round_row, 'from_token_decimals') else None,
                    "want_token": round_row.want_token if hasattr(round_row, 'want_token') else None,
                    "want_token_symbol": round_row.want_token_symbol if hasattr(round_row, 'want_token_symbol') else None,
                    "want_token_name": round_row.want_token_name if hasattr(round_row, 'want_token_name') else None,
                    "want_token_decimals": round_row.want_token_decimals if hasattr(round_row, 'want_token_decimals') else None,
                    "kicked_at": kicked_at_iso,
                    "round_start": (
                        int(round_row.round_start.timestamp()) if hasattr(round_row, 'round_start') and round_row.round_start is not None and hasattr(round_row.round_start, 'timestamp')
                        else int(round_row.round_start) if hasattr(round_row, 'round_start') and round_row.round_start is not None and isinstance(round_row.round_start, (int, float))
                        else int(round_row.kicked_at)
                    ),
                    "round_end": (
                        int(round_row.round_end.timestamp()) if hasattr(round_row, 'round_end') and round_row.round_end is not None and hasattr(round_row.round_end, 'timestamp')
                        else int(round_row.round_end) if hasattr(round_row, 'round_end') and round_row.round_end is not None and isinstance(round_row.round_end, (int, float))
                        else None
                    ),
                    "initial_available": str(round_row.initial_available) if round_row.initial_available else "0",
                    "transaction_hash": round_row.transaction_hash if hasattr(round_row, 'transaction_hash') else None,
                    "is_active": round_row.is_active or False,
                    "total_takes": round_row.total_takes or 0,
                    "total_pnl_usd": str(round_row.total_pnl_usd) if hasattr(round_row, 'total_pnl_usd') and round_row.total_pnl_usd is not None else "0",
                    "avg_pnl_percent": float(round_row.avg_pnl_percent) if hasattr(round_row, 'avg_pnl_percent') and round_row.avg_pnl_percent is not None else None
                }
                if hasattr(round_row, 'time_remaining'):
                    round_info["time_remaining"] = round_row.time_remaining
                if hasattr(round_row, 'seconds_elapsed'):
                    round_info["seconds_elapsed"] = round_row.seconds_elapsed
                rounds.append(round_info)
            
            logger.info(f"Successfully loaded {len(rounds)} rounds from database for {auction_address}")
            return {
                "auction": auction_address,
                "from_token": from_token,
                "rounds": rounds,
                "total": len(rounds)
            }

    async def get_system_stats(self, chain_id: Optional[int] = None) -> SystemStats:
        """Get system stats from database with short in-process caching."""
        try:
            # Simple per-process cache to avoid hammering DB on frequent polls
            ttl = int(os.getenv('STATS_CACHE_SEC', os.getenv('DEV_STATS_CACHE_SEC', '5')))
            cache_key = f"stats:{chain_id if chain_id is not None else 'all'}"
            now = _time.time()
            if not hasattr(self, '_stats_cache'):
                self._stats_cache = {}
            entry = self._stats_cache.get(cache_key)
            if entry and now - entry['ts'] < ttl:
                return entry['val']

            async with AsyncSessionLocal() as session:
                stats_data = await DatabaseQueries.get_system_stats(session, chain_id)
                if not stats_data:
                    val = SystemStats(
                        total_auctions=0,
                        active_auctions=0,
                        unique_tokens=0,
                        total_rounds=0,
                        total_takes=0,
                        total_participants=0,
                        total_volume_usd=0.0
                    )
                else:
                    val = SystemStats(
                        total_auctions=stats_data.total_auctions or 0,
                        active_auctions=stats_data.active_auctions or 0,
                        unique_tokens=stats_data.unique_tokens or 0,
                        total_rounds=stats_data.total_rounds or 0,
                        total_takes=stats_data.total_takes or 0,
                        total_participants=stats_data.total_participants or 0,
                        total_volume_usd=float(stats_data.total_volume_usd) if stats_data.total_volume_usd else 0.0
                    )

                self._stats_cache[cache_key] = {'ts': now, 'val': val}
                return val
        except Exception as e:
            logger.error(f"Database error in get_system_stats: {e}")
            raise Exception(f"Failed to fetch system stats from database: {e}")

    async def get_recent_takes(self, limit: int = 100, chain_id: Optional[int] = None) -> List[Take]:
        """Get recent takes across all auctions using vw_takes"""
        try:
            async with AsyncSessionLocal() as session:
                rows = await DatabaseQueries.get_recent_takes(session, limit, chain_id)
                takes: List[Take] = []
                for r in rows:
                    takes.append(
                        Take(
                            take_id=str(r.take_id) if r.take_id else f"take_{r.take_seq}",
                            auction=r.auction_address,
                            chain_id=r.chain_id,
                            round_id=r.round_id,
                            take_seq=r.take_seq,
                            taker=r.taker,
                            amount_taken=str(r.amount_taken),
                            amount_paid=str(r.amount_paid),
                            price=str(r.price),
                            timestamp=r.timestamp.isoformat() if hasattr(r.timestamp, 'isoformat') else str(r.timestamp),
                            tx_hash=r.transaction_hash,
                            block_number=r.block_number,
                            from_token=r.from_token,
                            to_token=r.to_token,
                            from_token_symbol=r.from_token_symbol if hasattr(r, 'from_token_symbol') else None,
                            from_token_name=r.from_token_name if hasattr(r, 'from_token_name') else None,
                            from_token_decimals=r.from_token_decimals if hasattr(r, 'from_token_decimals') else None,
                            to_token_symbol=r.to_token_symbol if hasattr(r, 'to_token_symbol') else None,
                            to_token_name=r.to_token_name if hasattr(r, 'to_token_name') else None,
                            to_token_decimals=r.to_token_decimals if hasattr(r, 'to_token_decimals') else None,
                            from_token_price_usd=str(r.from_token_price_usd) if getattr(r, 'from_token_price_usd', None) is not None else None,
                            want_token_price_usd=str(r.want_token_price_usd) if getattr(r, 'want_token_price_usd', None) is not None else None,
                            amount_taken_usd=str(r.amount_taken_usd) if getattr(r, 'amount_taken_usd', None) is not None else None,
                            amount_paid_usd=str(r.amount_paid_usd) if getattr(r, 'amount_paid_usd', None) is not None else None,
                            price_differential_usd=str(r.price_differential_usd) if getattr(r, 'price_differential_usd', None) is not None else None,
                            price_differential_percent=float(r.price_differential_percent) if getattr(r, 'price_differential_percent', None) is not None else None
                        )
                    )
                return takes
        except Exception as e:
            logger.error(f"Database error in get_recent_takes: {e}")
            raise Exception(f"Failed to fetch recent takes from database: {e}")

# Data service factory
def get_data_provider(force_mode: Optional[str] = None) -> DataProvider:
    """Get the appropriate data provider based on configuration and force_mode
    
    Args:
        force_mode: "mock" to force MockDataProvider, None for default database mode
    """
    # Always honor explicit mock request
    if force_mode == "mock":
        logger.info("Using MockDataProvider (forced by --mock flag)")
        return MockDataProvider()
    
    # Respect application mock mode even if force_mode is not set
    try:
        from monitoring.api.config import get_settings
        _settings = get_settings()
        if hasattr(_settings, 'app_mode') and str(_settings.app_mode).lower().endswith('mock'):
            logger.info("App is in MOCK mode; using MockDataProvider")
            return MockDataProvider()
    except Exception:
        pass

    # Default: use database
    try:
        from monitoring.api.config import get_settings
        settings = get_settings()
        database_url = settings.get_effective_database_url()
        
        if not database_url:
            raise RuntimeError("Database URL required but not configured")
        
        logger.info(f"Using DatabaseDataProvider with database: {database_url}")
        return DatabaseDataProvider()
            
    except Exception as e:
        logger.error(f"Database provider initialization failed: {e}")
        raise RuntimeError(f"Cannot initialize database provider: {e}")


if __name__ == "__main__":
    # Test database connection
    async def test_connection():
        success = await init_database()
        if success:
            async with AsyncSessionLocal() as session:
                stats = await DatabaseQueries.get_system_stats(session)
                logger.info(f"System stats: {dict(stats) if stats else 'No data yet'}")
                
                # Test the query methods
                all_auctions = await DatabaseQueries.get_auctions(session, active_only=False)
                active_auctions = await DatabaseQueries.get_auctions(session, active_only=True)
                logger.info(f"Total auctions: {len(all_auctions)}, Active auctions: {len(active_auctions)}")
                
                tokens = await DatabaseQueries.get_all_tokens(session)
                logger.info(f"Total tokens: {len(tokens)}")
                
                recent_takes = await DatabaseQueries.get_recent_takes_activity(session, limit=5)
                logger.info(f"Recent takes: {len(recent_takes)}")

    asyncio.run(test_connection())
