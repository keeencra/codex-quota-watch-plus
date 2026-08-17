from __future__ import annotations

import json
import re
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .models import HourBucket, TokenStats

SENSITIVE_NAME_PATTERNS = re.compile(
    r"(auth|token|credential|secret|cookie|session_key|api[_-]?key)", re.IGNORECASE
)

SESSION_EXTENSIONS = {".jsonl", ".json", ".log", ".txt"}

INPUT_KEYS = {
    "input_tokens",
    "prompt_tokens",
    "num_input_tokens",
    "tokens_input",
}
OUTPUT_KEYS = {
    "output_tokens",
    "completion_tokens",
    "num_output_tokens",
    "tokens_output",
}
CACHE_READ_KEYS = {
    "cache_read_input_tokens",
    "cached_input_tokens",
    "input_cached_tokens",
    "cache_read_tokens",
}
CACHE_CREATION_KEYS = {
    "cache_creation_input_tokens",
    "cache_creation_tokens",
    "cache_write_tokens",
}
TIMESTAMP_KEYS = {"timestamp", "created_at", "updated_at", "time", "ts", "datetime"}
SKIP_TOKEN_SUBTREES = {"total_token_usage", "iterations"}
PREFERRED_USAGE_PATHS = (
    ("payload", "info", "last_token_usage"),
    ("message", "usage"),
    ("usage",),
    ("response", "usage"),
)


@dataclass
class ScanResult:
    today: TokenStats
    hourly: list[HourBucket]


def _now_local() -> datetime:
    return datetime.now().astimezone()


def _parse_dt(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.astimezone() if value.tzinfo else value.replace(tzinfo=timezone.utc).astimezone()
    if isinstance(value, (int, float)):
        # Accept seconds or milliseconds.
        try:
            ts = value / 1000 if value > 10_000_000_000 else value
            return datetime.fromtimestamp(ts, tz=timezone.utc).astimezone()
        except Exception:
            return None
    if isinstance(value, str):
        s = value.strip()
        if not s:
            return None
        if s.isdigit():
            return _parse_dt(int(s))
        try:
            if s.endswith("Z"):
                s = s[:-1] + "+00:00"
            return datetime.fromisoformat(s).astimezone()
        except Exception:
            return None
    return None


def _iter_json_objects(path: Path) -> Iterable[dict[str, Any]]:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return []

    if path.suffix == ".json":
        try:
            loaded = json.loads(text)
            if isinstance(loaded, dict):
                return [loaded]
            if isinstance(loaded, list):
                return [x for x in loaded if isinstance(x, dict)]
        except Exception:
            pass

    out: list[dict[str, Any]] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or not line.startswith(("{", "[")):
            continue
        try:
            loaded = json.loads(line)
        except Exception:
            continue
        if isinstance(loaded, dict):
            out.append(loaded)
        elif isinstance(loaded, list):
            out.extend(x for x in loaded if isinstance(x, dict))
    return out


def _walk_values(obj: Any) -> Iterable[tuple[str | None, Any]]:
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield str(k), v
            yield from _walk_values(v)
    elif isinstance(obj, list):
        for item in obj:
            yield None, item
            yield from _walk_values(item)


def _find_first(obj: Any, keys: set[str]) -> Any:
    if isinstance(obj, dict):
        for k, v in obj.items():
            if str(k) in keys and v not in (None, ""):
                return v
        for v in obj.values():
            found = _find_first(v, keys)
            if found not in (None, ""):
                return found
    elif isinstance(obj, list):
        for item in obj:
            found = _find_first(item, keys)
            if found not in (None, ""):
                return found
    return None


def _get_path(obj: Any, path: tuple[str, ...]) -> Any:
    current = obj
    for part in path:
        if not isinstance(current, dict):
            return None
        current = current.get(part)
    return current


def _add_direct_token_fields(stats: TokenStats, obj: dict[str, Any]) -> None:
    for key, value in obj.items():
        if not isinstance(value, (int, float)):
            continue
        ivalue = int(value)
        if ivalue < 0:
            continue
        lk = key.lower()
        if lk in INPUT_KEYS:
            stats.input_tokens += ivalue
        elif lk in OUTPUT_KEYS:
            stats.output_tokens += ivalue
        elif lk in CACHE_READ_KEYS:
            stats.cache_read_tokens += ivalue
        elif lk in CACHE_CREATION_KEYS:
            stats.cache_creation_tokens += ivalue


def _walk_token_values(obj: Any) -> Iterable[tuple[str, int]]:
    if isinstance(obj, dict):
        for key, value in obj.items():
            lk = str(key).lower()
            if lk in SKIP_TOKEN_SUBTREES:
                continue
            if isinstance(value, (int, float)):
                ivalue = int(value)
                if ivalue >= 0:
                    yield lk, ivalue
                continue
            yield from _walk_token_values(value)
    elif isinstance(obj, list):
        for item in obj:
            yield from _walk_token_values(item)


def _tokens_from_obj(obj: Any) -> tuple[TokenStats, datetime | None]:
    stats = TokenStats()
    event_ts = _parse_dt(_find_first(obj, TIMESTAMP_KEYS))

    # Prefer per-event usage containers. Avoid recursively adding cumulative totals
    # and nested breakdowns such as Codex total_token_usage iterations.
    for path in PREFERRED_USAGE_PATHS:
        usage = _get_path(obj, path)
        if isinstance(usage, dict):
            _add_direct_token_fields(stats, usage)
            if stats.total_tokens:
                return stats, event_ts

    for lk, ivalue in _walk_token_values(obj):
        if lk in INPUT_KEYS:
            stats.input_tokens += ivalue
        elif lk in OUTPUT_KEYS:
            stats.output_tokens += ivalue
        elif lk in CACHE_READ_KEYS:
            stats.cache_read_tokens += ivalue
        elif lk in CACHE_CREATION_KEYS:
            stats.cache_creation_tokens += ivalue
    return stats, event_ts


def _candidate_files(root: Path, max_files: int) -> list[Path]:
    if not root.exists():
        return []
    files: list[Path] = []
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if p.suffix.lower() not in SESSION_EXTENSIONS:
            continue
        rel = str(p.relative_to(root)) if p.is_relative_to(root) else str(p)
        if SENSITIVE_NAME_PATTERNS.search(rel):
            continue
        files.append(p)
    files.sort(key=lambda x: x.stat().st_mtime if x.exists() else 0, reverse=True)
    return files[:max_files]


def scan_usage_dir(
    root: Path,
    *,
    max_files: int = 300,
) -> ScanResult:
    today_date = _now_local().date()
    today = TokenStats()
    buckets = [HourBucket(hour=h) for h in range(24)]

    for path in _candidate_files(root, max_files=max_files):
        try:
            mtime = path.stat().st_mtime
        except Exception:
            continue
        objects = list(_iter_json_objects(path))
        if not objects:
            continue

        file_updated_at = datetime.fromtimestamp(mtime, tz=timezone.utc).astimezone()
        for obj in objects:
            token_stats, event_ts = _tokens_from_obj(obj)
            ts = event_ts or file_updated_at
            if ts and ts.date() == today_date:
                today.input_tokens += token_stats.input_tokens
                today.output_tokens += token_stats.output_tokens
                today.cache_read_tokens += token_stats.cache_read_tokens
                today.cache_creation_tokens += token_stats.cache_creation_tokens
                h = ts.hour
                buckets[h].input_tokens += token_stats.input_tokens
                buckets[h].output_tokens += token_stats.output_tokens
                buckets[h].cache_tokens += token_stats.cache_tokens
                buckets[h].total_tokens += token_stats.total_tokens

    return ScanResult(today=today, hourly=buckets)
