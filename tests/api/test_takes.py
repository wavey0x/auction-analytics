import os
import pytest


TAKE_PATH = os.getenv('TEST_TAKE_PATH')  # e.g., /takes/1/0x.../5/1


@pytest.mark.anyio
@pytest.mark.skipif(not TAKE_PATH, reason="TEST_TAKE_PATH not set; skipping take details check")
async def test_take_details_status(client):
    r = await client.get(TAKE_PATH)
    # Accept 200 (found) or 404 (not found); forbid 5xx
    assert r.status_code < 500
    if r.status_code == 200:
        data = r.json()
        assert 'take_id' in data

