import os
import asyncio
import pytest
import httpx


BASE_URL = os.getenv("BASE_URL", "http://127.0.0.1:8000")


@pytest.fixture(scope="session")
def base_url() -> str:
    return BASE_URL.rstrip("/")


@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture()
async def client(base_url: str):
    async with httpx.AsyncClient(base_url=base_url, timeout=httpx.Timeout(5.0, read=5.0)) as c:
        yield c

