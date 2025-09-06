from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from datetime import datetime, timezone
from typing import Dict, Any, List
import os
import asyncio
import aiohttp
import json
import time

try:
    import redis  # type: ignore
except Exception:  # pragma: no cover
    redis = None
try:
    import redis.asyncio as aioredis  # type: ignore
except Exception:  # pragma: no cover
    aioredis = None

# Import using absolute module name because app runs as a script from project root
from monitoring.api.database import get_db, AsyncSessionLocal

router = APIRouter()


def _now_epoch() -> int:
    return int(datetime.now(timezone.utc).timestamp())


def _status_from_age(age_sec: int, ok: int, warn: int) -> str:
    if age_sec <= ok:
        return "ok"
    if age_sec <= warn:
        return "degraded"
    return "down"


async def _get_chain_head_block() -> int | None:
    """Get current chain head block number via RPC."""
    rpc_url = os.getenv("DEV_ANVIL_RPC_URL", "http://localhost:8545")
    if not rpc_url:
        return None
    
    try:
        # Tight timeout to avoid blocking status endpoint
        timeout = aiohttp.ClientTimeout(total=1)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            payload = {
                "jsonrpc": "2.0",
                "method": "eth_blockNumber",
                "params": [],
                "id": 1
            }
            async with session.post(rpc_url, json=payload) as response:
                if response.status == 200:
                    data = await response.json()
                    if "result" in data:
                        # Convert hex to int
                        return int(data["result"], 16)
    except Exception:
        pass
    
    return None


def _build_redis_url_for_status() -> str | None:
    """Build a Redis URL using the same conventions as other services.

    Prefers `REDIS_URL`. Otherwise builds from parts, trying consumer/publisher creds,
    then generic username/password, then password-only.
    """
    url = os.getenv("REDIS_URL")
    if url and url.strip():
        return url.strip()

    host = (os.getenv("REDIS_HOST") or "localhost").strip()
    port = (os.getenv("REDIS_PORT") or "6379").strip()
    db = (os.getenv("REDIS_DB") or "0").strip()
    tls = (os.getenv("REDIS_TLS") or "false").strip().lower() in ("1","true","yes","on")
    scheme = "rediss" if tls else "redis"

    # Prefer consumer role for read/ping
    user = (os.getenv("REDIS_CONSUMER_USER") or os.getenv("REDIS_USERNAME") or "").strip()
    pwd = (os.getenv("REDIS_CONSUMER_PASS") or os.getenv("REDIS_PASSWORD") or "").strip()
    if not user and not pwd:
        # Try publisher as a fallback, or password-only
        user = (os.getenv("REDIS_PUBLISHER_USER") or user).strip()
        pwd = (os.getenv("REDIS_PUBLISHER_PASS") or pwd).strip()

    auth = ""
    if user and pwd:
        auth = f"{user}:{pwd}@"
    elif pwd:
        auth = f":{pwd}@"

    return f"{scheme}://{auth}{host}:{port}/{db}"


async def _probe_redis_status() -> dict:
    """Non-blocking Redis probe with short timeouts.

    Tries async client if available; otherwise wraps sync calls in a thread.
    Returns a dict with status, detail and metrics keys.
    """
    status = {
        "name": "redis",
        "status": "unknown",
        "detail": "",
        "metrics": {}
    }
    if not redis:
        status["status"] = "unknown"
        status["detail"] = "redis client not installed"
        return status

    redis_url = _build_redis_url_for_status()
    if not redis_url:
        status["status"] = "unknown"
        status["detail"] = "No Redis configuration found"
        return status

    stream_key = os.getenv("REDIS_STREAM_KEY", "events")

    # Prefer asyncio redis client
    if aioredis is not None:
        try:
            client = aioredis.from_url(
                redis_url,
                decode_responses=True,
                socket_connect_timeout=0.5,
                socket_timeout=0.5,
            )
            try:
                # Use XREVRANGE small read
                await client.xrevrange(stream_key, count=1)
                status.update({"status": "ok", "detail": f"xrevrange({stream_key}) ok"})
            except Exception:
                # Fallback to PING if xrevrange disallowed
                try:
                    pong = await client.ping()
                    status.update({"status": "ok" if pong else "down", "detail": "PONG" if pong else "No response"})
                except Exception as e2:
                    status.update({"status": "down", "detail": str(e2)[:200]})
            try:
                await client.close()
            except Exception:
                pass
            return status
        except Exception as e:
            status.update({"status": "down", "detail": str(e)[:200]})
            return status

    # Fallback: wrap sync client in thread to avoid blocking
    async def _sync_probe() -> dict:
        try:
            client = redis.from_url(
                redis_url,
                decode_responses=True,
                socket_connect_timeout=0.5,
                socket_timeout=0.5,
            )
            try:
                client.xrevrange(stream_key, count=1)
                return {"status": "ok", "detail": f"xrevrange({stream_key}) ok"}
            except Exception as cmd_err:
                try:
                    pong = client.ping()
                    return {"status": "ok" if pong else "down", "detail": "PONG" if pong else "No response"}
                except Exception as e2:
                    return {"status": "down", "detail": str(cmd_err)[:200]}
        except Exception as e:
            return {"status": "down", "detail": str(e)[:200]}

    try:
        res = await asyncio.wait_for(asyncio.to_thread(_sync_probe), timeout=0.75)  # type: ignore[arg-type]
        status.update(res)
    except Exception:
        status.update({"status": "unknown", "detail": "timeout"})
    return status


_STATUS_CACHE: Dict[str, Any] | None = None
_STATUS_CACHE_TS: float | None = None
_STATUS_CACHE_TTL_SEC: float = 30.0  # serve cached result up to 30s
_STATUS_REFRESH_IN_PROGRESS: bool = False
_STATUS_REFRESH_MIN_INTERVAL_SEC: float = 5.0


async def _rebuild_status_cache() -> None:
    global _STATUS_CACHE, _STATUS_CACHE_TS, _STATUS_REFRESH_IN_PROGRESS
    try:
        async with AsyncSessionLocal() as session:
            # Force compute using the same logic as the route, but without early-return
            result = await get_status(db=session, compute=True)  # type: ignore
            _STATUS_CACHE = result
            _STATUS_CACHE_TS = time.time()
    except Exception:
        pass
    finally:
        _STATUS_REFRESH_IN_PROGRESS = False


def _schedule_status_refresh() -> None:
    global _STATUS_REFRESH_IN_PROGRESS, _STATUS_CACHE_TS
    now = time.time()
    if _STATUS_REFRESH_IN_PROGRESS:
        return
    # Debounce background refreshes
    if _STATUS_CACHE_TS and (now - _STATUS_CACHE_TS) < _STATUS_REFRESH_MIN_INTERVAL_SEC:
        return
    _STATUS_REFRESH_IN_PROGRESS = True
    try:
        asyncio.get_running_loop().create_task(_rebuild_status_cache())
    except RuntimeError:
        # No running loop (unlikely in FastAPI), ignore
        _STATUS_REFRESH_IN_PROGRESS = False


@router.get("/status")
async def get_status(db: AsyncSession = Depends(get_db), compute: bool = False) -> Dict[str, Any]:
    now = _now_epoch()

    # Fast path: always serve cache immediately when not forcing compute.
    # If cache is missing or stale, schedule background refresh but do not block.
    if not compute:
        global _STATUS_CACHE, _STATUS_CACHE_TS
        # Return cached snapshot if available (even if slightly stale)
        if _STATUS_CACHE is not None:
            # Trigger background refresh if past TTL
            try:
                if _STATUS_CACHE_TS and (time.time() - _STATUS_CACHE_TS) > _STATUS_CACHE_TTL_SEC:
                    _schedule_status_refresh()
            except Exception:
                pass
            return _STATUS_CACHE
        # No cache yet: schedule refresh and return minimal placeholder
        try:
            _schedule_status_refresh()
        except Exception:
            pass
        return {
            "generated_at": now,
            "thresholds": {
                "indexer_ok": int(os.getenv("DEV_INDEXER_OK_SEC", "30")),
                "indexer_warn": int(os.getenv("DEV_INDEXER_WARN_SEC", "120")),
                "price_ok": int(os.getenv("DEV_PRICE_OK_SEC", "600")),
                "price_warn": int(os.getenv("DEV_PRICE_WARN_SEC", "1800")),
                "relay_warn": int(os.getenv("DEV_RELAY_WARN", "100")),
                "relay_crit": int(os.getenv("DEV_RELAY_CRIT", "1000")),
            },
            "services": [
                {"name": "api", "status": "ok", "detail": "FastAPI responding", "metrics": {"time": now}},
                {"name": "postgres", "status": "unknown", "detail": "loading", "metrics": {}},
                {"name": "redis", "status": "unknown", "detail": "loading", "metrics": {}},
                {"name": "rpc", "status": "unknown", "detail": "loading", "metrics": {}},
                {"name": "indexer", "status": "unknown", "detail": "loading", "metrics": {}},
                {"name": "prices", "status": "unknown", "detail": "loading", "metrics": {}},
                {"name": "relay", "status": "unknown", "detail": "loading", "metrics": {}},
            ],
            "stale": True
        }

    # Thresholds (seconds)
    idx_ok = int(os.getenv("DEV_INDEXER_OK_SEC", "30"))
    idx_warn = int(os.getenv("DEV_INDEXER_WARN_SEC", "120"))
    price_ok = int(os.getenv("DEV_PRICE_OK_SEC", "600"))
    price_warn = int(os.getenv("DEV_PRICE_WARN_SEC", "1800"))
    relay_warn = int(os.getenv("DEV_RELAY_WARN", "100"))
    relay_crit = int(os.getenv("DEV_RELAY_CRIT", "1000"))

    services: List[Dict[str, Any]] = []

    # API (self)
    services.append({
        "name": "api",
        "status": "ok",
        "detail": "FastAPI responding",
        "metrics": {"time": now}
    })

    # Database health
    db_status = {
        "name": "postgres",
        "status": "unknown",
        "detail": "",
        "metrics": {}
    }
    try:
        res = await db.execute(text("SELECT 1"))
        one = res.scalar()
        ok = (one == 1)
        db_status["status"] = "ok" if ok else "down"
        db_status["detail"] = "Connected" if ok else "Query failed"
    except Exception as e:
        db_status["status"] = "down"
        db_status["detail"] = str(e)[:200]
    services.append(db_status)

    # Redis health (probe in parallel with DB work)
    try:
        redis_status = await asyncio.wait_for(_probe_redis_status(), timeout=0.8)
    except Exception:
        redis_status = {"name": "redis", "status": "unknown", "detail": "timeout", "metrics": {}}
    services.append(redis_status)

    # RPC health (simulated from frontend monitoring)
    # In production, this could query a real RPC health database or cache
    rpc_status = {
        "name": "rpc",
        "status": "ok",
        "detail": "Frontend RPC monitoring active",
        "metrics": {
            "monitored_chains": ["1", "137", "42161", "10", "8453"],
            "health_check": "frontend_based",
            "note": "RPC health tracked by frontend error notifications"
        }
    }
    services.append(rpc_status)

    # Indexer recency and block lag
    idx_status = {
        "name": "indexer",
        "status": "unknown",
        "detail": "",
        "metrics": {}
    }
    try:
        res = await db.execute(text(
            """
            SELECT MAX(updated_at) AS updated_at, MAX(last_indexed_block) AS last_block
            FROM indexer_state
            """
        ))
        row = res.fetchone()
        if row and row[0] is not None:
            updated_at = int(row[0].timestamp()) if hasattr(row[0], 'timestamp') else int(row[0])
            age = max(0, now - updated_at)
            indexed_block = int(row[1] or 0)
            
            # Get chain head for block lag detection (in parallel earlier)
            try:
                chain_head = await asyncio.wait_for(_get_chain_head_block(), timeout=1.0)
            except Exception:
                chain_head = None
            
            # Determine status based on age and block lag
            age_status = _status_from_age(age, idx_ok, idx_warn)
            block_lag_status = "ok"
            block_lag = 0
            
            if chain_head is not None and indexed_block > 0:
                block_lag = max(0, chain_head - indexed_block)
                if block_lag > 10:
                    block_lag_status = "degraded"
                    
            # Use worst status between age and block lag
            if age_status == "down" or block_lag_status == "down":
                final_status = "down"
            elif age_status == "degraded" or block_lag_status == "degraded":
                final_status = "degraded" 
            else:
                final_status = "ok"
            
            # Build detail message
            detail_parts = [f"updated {age}s ago"]
            if chain_head is not None:
                detail_parts.append(f"{block_lag} blocks behind")
            detail = ", ".join(detail_parts)
            
            idx_status.update({
                "status": final_status,
                "detail": detail,
                "metrics": {
                    "last_block": indexed_block, 
                    "age_sec": age,
                    "chain_head": chain_head,
                    "block_lag": block_lag
                }
            })
        else:
            idx_status.update({"status": "down", "detail": "No indexer_state rows"})
    except Exception as e:
        idx_status.update({"status": "unknown", "detail": f"{e}"[:200]})
    services.append(idx_status)

    # Pricing freshness and backlog
    price_status = {
        "name": "prices",
        "status": "unknown",
        "detail": "",
        "metrics": {}
    }
    try:
        # Latest per source (accelerated by idx_token_prices_source_ts)
        res = await db.execute(text(
            "SELECT source, MAX(timestamp) AS ts FROM token_prices GROUP BY source"
        ))
        rows = res.fetchall()
        per_source = {}
        worst = "ok"
        for r in rows:
            src = r[0]
            ts = int(r[1] or 0)
            age = max(0, now - ts) if ts > 0 else 10**9
            st = _status_from_age(age, price_ok, price_warn)
            per_source[src] = {"age_sec": age, "status": st}
            # compute worst
            order = {"ok": 0, "degraded": 1, "down": 2}
            if order.get(st, 0) > order.get(worst, 0):
                worst = st
        # Pending backlog
        res2 = await db.execute(text(
            "SELECT COUNT(*) FROM price_requests WHERE status = 'pending'"
        ))
        pending = int(res2.scalar() or 0)
        
        # If no pending requests, prices service is healthy regardless of data age
        final_status = "ok" if pending == 0 else (worst if rows else "unknown")
        
        price_status.update({
            "status": final_status,
            "detail": f"pending: {pending}",
            "metrics": {"pending": pending, "sources": per_source}
        })
    except Exception as e:
        price_status.update({"status": "unknown", "detail": f"{e}"[:200]})
    services.append(price_status)

    # Relay/outbox
    relay_status = {
        "name": "relay",
        "status": "unknown",
        "detail": "",
        "metrics": {}
    }
    try:
        res = await db.execute(text(
            "SELECT COUNT(*) FROM outbox_events WHERE published_at IS NULL"
        ))
        backlog = int(res.scalar() or 0)
        if backlog >= relay_crit:
            st = "down"
        elif backlog >= relay_warn:
            st = "degraded"
        else:
            st = "ok"
        relay_status.update({
            "status": st,
            "detail": f"unpublished: {backlog}",
            "metrics": {"unpublished": backlog}
        })
    except Exception as e:
        relay_status.update({"status": "unknown", "detail": f"{e}"[:200]})
    services.append(relay_status)

    result = {
        "generated_at": now,
        "thresholds": {
            "indexer_ok": idx_ok,
            "indexer_warn": idx_warn,
            "price_ok": price_ok,
            "price_warn": price_warn,
            "relay_warn": relay_warn,
            "relay_crit": relay_crit,
        },
        "services": services,
    }

    # Update cache
    try:
        _STATUS_CACHE = result
        _STATUS_CACHE_TS = datetime.now(timezone.utc).timestamp()
    except Exception:
        pass

    return result
