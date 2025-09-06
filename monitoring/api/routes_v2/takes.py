from fastapi import APIRouter, Query, HTTPException
from typing import Optional, Tuple, Any, Dict
import time

from monitoring.api.database import get_data_provider, DataProvider

router = APIRouter(prefix="/takes", tags=["Takes"])

# Tiny in-process cache for recent takes
_TAKES_CACHE: Dict[Tuple[int, Optional[int], bool], Any] = {}
_TAKES_CACHE_TS: Dict[Tuple[int, Optional[int], bool], float] = {}
_TAKES_CACHE_TTL = 5.0  # seconds


@router.get("")
async def list_takes(
    limit: int = Query(50, ge=1, le=500),
    chain_id: Optional[int] = Query(None),
    minimal: bool = Query(False, description="Return minimal fields for list view")
):
    # Serve from cache when fresh
    cache_key = (int(limit), int(chain_id) if chain_id is not None else None, bool(minimal))
    now = time.time()
    try:
        ts = _TAKES_CACHE_TS.get(cache_key)
        if ts and (now - ts) < _TAKES_CACHE_TTL:
            return _TAKES_CACHE[cache_key]
    except Exception:
        pass

    provider: DataProvider = get_data_provider()
    rows = await provider.get_recent_takes(limit, chain_id)

    if minimal:
        # Reduce payload to essential fields used in tables/cards
        result = [
            {
                "take_id": getattr(r, 'take_id', None),
                "auction": getattr(r, 'auction', None) or getattr(r, 'auction_address', None),
                "chain_id": getattr(r, 'chain_id', None),
                "round_id": getattr(r, 'round_id', None),
                "take_seq": getattr(r, 'take_seq', None),
                "taker": getattr(r, 'taker', None),
                "from_token": getattr(r, 'from_token', None),
                "to_token": getattr(r, 'to_token', None),
                "from_token_symbol": getattr(r, 'from_token_symbol', None),
                "to_token_symbol": getattr(r, 'to_token_symbol', None),
                "amount_taken": getattr(r, 'amount_taken', None),
                "amount_paid": getattr(r, 'amount_paid', None),
                "price": getattr(r, 'price', None),
                "timestamp": getattr(r, 'timestamp', None),
                "tx_hash": getattr(r, 'tx_hash', None) or getattr(r, 'transaction_hash', None),
                "block_number": getattr(r, 'block_number', None),
            }
            for r in rows
        ]
    else:
        result = rows

    # Update cache
    try:
        _TAKES_CACHE[cache_key] = result
        _TAKES_CACHE_TS[cache_key] = now
    except Exception:
        pass

    return result


def _parse_take_id(take_id: str):
    # Expected: chainId:auctionAddress:roundId:takeSeq
    parts = take_id.split(":")
    if len(parts) != 4:
        raise HTTPException(status_code=400, detail="take_id must be 'chainId:auctionAddress:roundId:takeSeq'")
    try:
        chain_id = int(parts[0])
        auction = parts[1]
        round_id = int(parts[2])
        take_seq = int(parts[3])
        return chain_id, auction, round_id, take_seq
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid take_id components")


@router.get("/{take_id}")
async def get_take(take_id: str):
    provider: DataProvider = get_data_provider()
    chain_id, auction, round_id, take_seq = _parse_take_id(take_id)
    # Reuse existing take details provider
    return await provider.get_take_details(chain_id, auction, round_id, take_seq)  # type: ignore
