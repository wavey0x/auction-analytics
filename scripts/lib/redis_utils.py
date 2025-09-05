#!/usr/bin/env python3
"""
Redis connection helpers with flexible auth.

Usage:
- Prefer REDIS_URL if set (supports redis://[username:password]@host:port/db?ssl=true)
- Otherwise, build from parts:
  REDIS_HOST, REDIS_PORT, REDIS_DB, REDIS_USERNAME, REDIS_PASSWORD, REDIS_TLS
"""

import os
from typing import Optional
from urllib.parse import urlparse, urlunparse


def build_redis_url(
    default_url: str = "redis://localhost:6379",
    role: str | None = None,
) -> str:
    # Gather role-specific creds (take precedence over generic)
    base_user = os.getenv("REDIS_USERNAME", "").strip()
    base_pass = os.getenv("REDIS_PASSWORD", "").strip()
    user = base_user
    pwd = base_pass
    if role == "publisher":
        user = (os.getenv("REDIS_PUBLISHER_USER") or user).strip()
        pwd = (os.getenv("REDIS_PUBLISHER_PASS") or pwd).strip()
    elif role == "consumer":
        user = (os.getenv("REDIS_CONSUMER_USER") or user).strip()
        pwd = (os.getenv("REDIS_CONSUMER_PASS") or pwd).strip()

    # If full URL provided, try to inject creds if missing
    raw_url = os.getenv("REDIS_URL")
    if raw_url and raw_url.strip():
        raw = raw_url.strip()
        try:
            parsed = urlparse(raw)
            # If REDIS_URL already has credentials, respect it
            if parsed.username or parsed.password:
                return raw
            # Inject role creds if provided
            if user or pwd:
                scheme = parsed.scheme or ("rediss" if (os.getenv("REDIS_TLS") or "false").strip().lower() in ("1","true","yes","on") else "redis")
                host = parsed.hostname or os.getenv("REDIS_HOST", "localhost").strip()
                port = parsed.port or int(os.getenv("REDIS_PORT", "6379").strip())
                path_db = parsed.path[1:] if parsed.path.startswith('/') else parsed.path
                db = path_db or os.getenv("REDIS_DB", "0").strip()
                netloc = f"{user}:{pwd}@{host}:{port}" if (user or pwd) else f"{host}:{port}"
                return urlunparse((scheme, netloc, f"/{db}", '', '', ''))
            # No creds to inject; return as is
            return raw
        except Exception:
            # Fall through to compose from parts
            pass

    # Compose from parts
    host = os.getenv("REDIS_HOST", "localhost").strip()
    port = os.getenv("REDIS_PORT", "6379").strip()
    db = os.getenv("REDIS_DB", "0").strip()
    tls = (os.getenv("REDIS_TLS") or "false").strip().lower() in ("1", "true", "yes", "on")
    scheme = "rediss" if tls else "redis"
    auth = f"{user}:{pwd}@" if (user or pwd) else ""
    return f"{scheme}://{auth}{host}:{port}/{db}"


def get_redis_client(decode_responses: bool = True, role: str | None = None):
    import redis

    url = build_redis_url(role=role)
    # Short, sane timeouts to avoid hanging checks
    return redis.from_url(
        url,
        decode_responses=decode_responses,
        socket_connect_timeout=3,
        socket_timeout=5,
    )
