import pytest


@pytest.mark.anyio
async def test_auctions_list(client):
    r = await client.get('/auctions')
    assert r.status_code == 200
    data = r.json()
    for k in ['auctions', 'total', 'page', 'per_page']:
        assert k in data


@pytest.mark.anyio
async def test_auctions_active(client):
    r = await client.get('/auctions?status=active')
    assert r.status_code == 200
    data = r.json()
    assert 'auctions' in data

