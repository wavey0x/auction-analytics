from fastapi import APIRouter, Query, Depends
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from monitoring.api.database import get_db

router = APIRouter(prefix="/rounds", tags=["Rounds"])


@router.get("")
async def list_rounds(
    limit: int = Query(50, ge=1, le=200),
    chain_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db)
):
    # Minimal round listing for discovery
    chain_filter = "WHERE r.chain_id = :chain_id" if chain_id else ""
    q = text(f"""
        SELECT r.auction_address, r.chain_id, r.round_id, r.kicked_at, r.from_token
        FROM rounds r
        {chain_filter}
        ORDER BY r.kicked_at DESC NULLS LAST
        LIMIT :limit
    """)
    params = {"limit": limit}
    if chain_id:
        params["chain_id"] = chain_id
    res = await db.execute(q, params)
    rows = [dict(row._mapping) for row in res.fetchall()]
    return {"rounds": rows, "total_count": len(rows), "page": 1, "limit": limit, "total_pages": 1, "has_next": False}


@router.get("/{round_id}")
async def get_round(round_id: int, chain_id: Optional[int] = Query(None), db: AsyncSession = Depends(get_db)):
    chain_filter = "AND r.chain_id = :chain_id" if chain_id else ""
    q = text(f"""
        SELECT r.*
        FROM rounds r
        WHERE r.round_id = :round_id {chain_filter}
        LIMIT 1
    """)
    params = {"round_id": round_id}
    if chain_id:
        params["chain_id"] = chain_id
    res = await db.execute(q, params)
    row = res.fetchone()
    if not row:
        return {"round": None}
    return {"round": dict(row._mapping)}
