import pytest


@pytest.mark.anyio
async def test_health(client):
    r = await client.get('/health')
    assert r.status_code == 200
    data = r.json()
    assert 'status' in data


@pytest.mark.anyio
async def test_status_services(client):
    r = await client.get('/status')
    assert r.status_code == 200
    data = r.json()
    assert isinstance(data.get('services', []), list)


@pytest.mark.anyio
async def test_system_stats(client):
    r = await client.get('/system/stats')
    assert r.status_code == 200
    data = r.json()
    for k in ['total_auctions', 'active_auctions', 'unique_tokens', 'total_rounds', 'total_takes', 'total_participants']:
        assert k in data

