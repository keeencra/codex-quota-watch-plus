from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any


def default_quota_cache_path(provider: str) -> Path:
    return Path(os.getenv("XDG_CACHE_HOME", "~/.cache")).expanduser() / "codex-quota-watch" / f"{provider}.json"


def write_quota_cache(
    *,
    provider: str,
    payload: dict[str, Any],
    source: str,
    cache_path: str | Path | None = None,
) -> None:
    path = Path(cache_path).expanduser() if cache_path else default_quota_cache_path(provider)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(
        json.dumps(
            {
                "provider": provider,
                "source": source,
                "cached_at": time.time(),
                "payload": payload,
            },
            ensure_ascii=False,
        )
    )
    tmp_path.replace(path)


def read_quota_cache(
    *,
    provider: str,
    max_age_seconds: int | None,
    cache_path: str | Path | None = None,
) -> tuple[dict[str, Any], dict[str, Any]] | None:
    path = Path(cache_path).expanduser() if cache_path else default_quota_cache_path(provider)
    try:
        raw = json.loads(path.read_text())
    except Exception:
        return None
    if raw.get("provider") != provider:
        return None
    cached_at = raw.get("cached_at")
    payload = raw.get("payload")
    if not isinstance(cached_at, (int, float)) or not isinstance(payload, dict):
        return None
    age = max(0, int(time.time() - float(cached_at)))
    if max_age_seconds is not None and age > max_age_seconds:
        return None
    return payload, {
        "cache_age_seconds": age,
        "cache_cached_at": float(cached_at),
        "cache_source": raw.get("source") or "unknown",
    }
