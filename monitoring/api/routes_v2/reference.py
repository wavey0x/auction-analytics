from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from monitoring.api.database import get_db, DatabaseQueries

router = APIRouter(prefix="", tags=["Reference"])


@router.get("/tokens")
async def get_tokens(db: AsyncSession = Depends(get_db)):
    rows = await DatabaseQueries.get_all_tokens(db)
    return {"tokens": [dict(r._mapping) for r in rows], "count": len(rows)}


@router.get("/chains")
async def get_chains():
    # Return all supported networks keyed by numeric chainId for consistency
    try:
        from monitoring.api.config import SUPPORTED_NETWORKS, get_network_config
        chains = {}
        for name, _meta in SUPPORTED_NETWORKS.items():
            cfg = get_network_config(name)
            cid = int(cfg.get("chain_id"))
            chains[cid] = {
                "chainId": cid,
                "name": cfg.get("name"),
                "shortName": cfg.get("short_name"),
                "icon": cfg.get("icon"),
                "explorer": cfg.get("explorer"),
            }
        return {"chains": chains, "count": len(chains)}
    except Exception:
        return {"chains": {}, "count": 0}
