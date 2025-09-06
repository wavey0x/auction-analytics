#!/usr/bin/env python3
"""
Utilities to normalize API responses (pagination and field aliases).
"""
from __future__ import annotations
from typing import Dict, Any


def normalize_pagination(data: Dict[str, Any]) -> Dict[str, Any]:
    """Ensure standard pagination keys exist on response dicts.

    Standard keys:
    - total_count, total_pages, page, limit, has_next

    Legacy keys (kept for compatibility):
    - total, per_page
    """
    # Legacy/input values
    total = int(data.get("total") or data.get("total_count") or 0)
    page = int(data.get("page") or 1)
    per_page = int(data.get("per_page") or data.get("limit") or 0) or 20

    # Derived
    total_pages = (total + per_page - 1) // per_page if total > 0 else 1
    has_next = page < total_pages

    # Standard keys
    data.setdefault("total_count", total)
    data.setdefault("total_pages", total_pages)
    data.setdefault("limit", per_page)
    data.setdefault("has_next", has_next)

    # Keep legacy mirrors
    data.setdefault("total", total)
    data.setdefault("per_page", per_page)
    return data


def alias_field(obj: Dict[str, Any], old: str, new: str) -> None:
    if old in obj and new not in obj:
        obj[new] = obj[old]


def normalize_take_item(item: Dict[str, Any]) -> Dict[str, Any]:
    """Normalize a single take dict field names (auction -> auction_address)."""
    alias_field(item, 'auction', 'auction_address')
    return item


def normalize_takes_array(container: Dict[str, Any], key: str = 'takes') -> Dict[str, Any]:
    arr = container.get(key)
    if isinstance(arr, list):
        for i in range(len(arr)):
            if isinstance(arr[i], dict):
                arr[i] = normalize_take_item(arr[i])
    return container

