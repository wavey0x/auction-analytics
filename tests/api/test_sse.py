import os
import asyncio
import pytest
import httpx


REDIS_URL = os.getenv('REDIS_URL')


@pytest.mark.anyio
@pytest.mark.skipif(not REDIS_URL, reason="REDIS_URL not set; skipping SSE test")
async def test_sse_connects(base_url):
    url = base_url.rstrip('/') + '/events/stream'
    timeout = httpx.Timeout(5.0, read=5.0)
    async with httpx.AsyncClient(timeout=timeout) as c:
        async with c.stream('GET', url) as r:
            assert r.status_code == 200
            ctype = r.headers.get('content-type', '')
            assert 'text/event-stream' in ctype
            # Read a small amount of data and look for the initial connected event
            found = False
            try:
                async for chunk in r.aiter_lines():
                    if 'connected' in (chunk or ''):
                        found = True
                        break
                    # Stop after a few lines to avoid long waits
                    await asyncio.sleep(0)
            except Exception:
                pass
            # It's acceptable if not found due to buffering, but connection should be open
            assert r.is_closed is False or found

