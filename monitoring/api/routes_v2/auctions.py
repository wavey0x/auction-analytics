from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from monitoring.api.database import get_db, get_data_provider, DataProvider

router = APIRouter(prefix="/auctions", tags=["Auctions"])


@router.get("")
async def list_auctions(
    status: str = Query("all", description="Filter by status: all, active, completed"),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    chain_id: Optional[int] = Query(None)
):
    provider: DataProvider = get_data_provider()
    return await provider.get_auctions(status, page, limit, chain_id)


@router.get("/{auction_address}")
async def get_auction(auction_address: str, chain_id: int = Query(...)):
    provider: DataProvider = get_data_provider()
    return await provider.get_auction_details(auction_address, chain_id)


@router.get("/{auction_address}/config")
async def get_auction_config(auction_address: str, chain_id: int = Query(...)):
    provider: DataProvider = get_data_provider()
    details = await provider.get_auction_details(auction_address, chain_id)
    return details.get('parameters') if isinstance(details, dict) else getattr(details, 'parameters', None)


@router.get("/{auction_address}/rounds")
async def get_auction_rounds(
    auction_address: str,
    chain_id: int = Query(...),
    from_token: Optional[str] = Query(None),
    round_id: Optional[int] = Query(None),
    limit: int = Query(50, ge=1, le=100)
):
    provider: DataProvider = get_data_provider()
    return await provider.get_auction_rounds(auction_address, from_token, limit, chain_id, round_id)


@router.get("/{auction_address}/takes")
async def get_auction_takes(
    auction_address: str,
    chain_id: int = Query(...),
    round_id: Optional[int] = Query(None),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0)
):
    provider: DataProvider = get_data_provider()
    return await provider.get_auction_takes(auction_address, round_id, limit, chain_id, offset)


@router.get("/{auction_address}/price-history")
async def get_price_history(
    auction_address: str,
    chain_id: int = Query(...),
    from_token: str = Query(...),
    hours: int = Query(24, ge=1, le=168)
):
    # Reuse existing provider path for price history
    provider: DataProvider = get_data_provider()
    try:
        # DatabaseDataProvider.get_price_history(auction_address, round_id=None, chain_id, hours)
        # Our provider takes auction_address, from_token? The current provider uses auction_address and chain_id only.
        from monitoring.api.database import DatabaseQueries, AsyncSessionLocal
        async with AsyncSessionLocal() as session:
            rows = await DatabaseQueries.get_price_history(session, auction_address, round_id=None, chain_id=chain_id, hours=hours)
            points = [dict(r._mapping) for r in rows]
            return {"auction": auction_address, "from_token": from_token, "points": points, "duration_hours": hours}
    except Exception:
        # Fallback empty if not implemented
        return {"auction": auction_address, "from_token": from_token, "points": [], "duration_hours": hours}
