from __future__ import annotations

import asyncio
import hmac
import re
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated, Literal

import uvicorn
from fastapi import Depends, FastAPI, Header, HTTPException, Query

from .models import QuotaStatus, TokenStats, UsageSnapshot
from .quota import cached_codex_quota, get_codex_quota
from .scanner import ScanResult, scan_usage_dir
from .settings import Settings

settings = Settings()

INSECURE_WATCH_TOKEN_PLACEHOLDERS = {
    "change-me-to-a-long-random-token",
    "replace-with-a-long-random-token",
    "PASTE_GENERATED_TOKEN_HERE",
    "<long-random-token>",
}
WATCH_TOKEN_MIN_LENGTH = 24
WATCH_TOKEN_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")
MAX_ERROR_MESSAGE_LENGTH = 240
FORCE_REFRESH_COALESCE_SECONDS = 5
ProviderName = Literal["codex"]


def is_valid_watch_token(token: str) -> bool:
    return (
        len(token) >= WATCH_TOKEN_MIN_LENGTH
        and token not in INSECURE_WATCH_TOKEN_PLACEHOLDERS
        and WATCH_TOKEN_PATTERN.fullmatch(token) is not None
    )


def validate_runtime_settings() -> None:
    token = settings.watch_token.strip() if settings.watch_token else ""
    if not is_valid_watch_token(token):
        raise RuntimeError("WATCH_TOKEN must be set to a long URL-safe random value before starting the Mac Agent")


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    validate_runtime_settings()
    yield


app = FastAPI(title="Codex Quota Watch Agent", version="0.1.0", lifespan=lifespan)

_cache: UsageSnapshot | None = None
_cache_time: datetime | None = None
_last_force_refresh_time: datetime | None = None
_cache_lock = asyncio.Lock()


def require_token(x_watch_token: Annotated[str | None, Header()] = None) -> None:
    token = settings.watch_token.strip() if settings.watch_token else ""
    if not is_valid_watch_token(token):
        raise HTTPException(status_code=500, detail="WATCH_TOKEN is not configured")
    provided = x_watch_token or ""
    if WATCH_TOKEN_PATTERN.fullmatch(provided) is None:
        raise HTTPException(status_code=401, detail="Invalid or missing x-watch-token")
    if not hmac.compare_digest(provided, token):
        raise HTTPException(status_code=401, detail="Invalid or missing x-watch-token")


def _empty_scan() -> ScanResult:
    return ScanResult(today=TokenStats(), hourly=[])


def _safe_error_message(exc: Exception) -> str:
    message = str(exc).strip() or exc.__class__.__name__
    for local_path, replacement in (
        (str(settings.codex_home), "<codex_home>"),
        (str(Path.home()), "~"),
    ):
        if local_path and local_path != "/":
            message = message.replace(local_path, replacement)
    if len(message) > MAX_ERROR_MESSAGE_LENGTH:
        message = message[: MAX_ERROR_MESSAGE_LENGTH - 3].rstrip() + "..."
    return message


def _provider_label(provider: ProviderName) -> str:
    return "Codex"


def _error_quota(provider: ProviderName, source: str, exc: Exception) -> QuotaStatus:
    return QuotaStatus(
        provider=provider,
        label=_provider_label(provider),
        status="error",
        source=source,
        error=_safe_error_message(exc),
    )


def _safe_scan(provider: ProviderName) -> tuple[ScanResult, QuotaStatus | None]:
    try:
        return (
            scan_usage_dir(
                settings.codex_home,
                max_files=settings.max_files_to_scan,
            ),
            None,
        )
    except Exception as exc:
        return _empty_scan(), _error_quota(provider, "scanner", exc)


async def _safe_quota(provider: ProviderName, getter: Callable[[Settings], Awaitable[QuotaStatus]]) -> QuotaStatus:
    try:
        return await asyncio.wait_for(
            asyncio.to_thread(lambda: asyncio.run(getter(settings))),
            timeout=settings.quota_provider_timeout_seconds,
        )
    except TimeoutError:
        if provider == "codex":
            cached = cached_codex_quota(settings, "CODEX_QUOTA_COMMAND cache")
            if cached is None:
                cached = cached_codex_quota(settings, "CODEX_QUOTA_COMMAND stale cache", allow_stale=True)
            if cached is not None:
                return cached
        return _error_quota(
            provider,
            "internal",
            RuntimeError(f"provider timed out after {settings.quota_provider_timeout_seconds}s"),
        )
    except Exception as exc:
        return _error_quota(provider, "internal", exc)


async def build_snapshot() -> UsageSnapshot:
    (codex_scan, codex_scan_error), codex_quota = await asyncio.gather(
        asyncio.to_thread(_safe_scan, "codex"),
        _safe_quota("codex", get_codex_quota),
    )
    if codex_scan_error is not None:
        codex_quota = codex_scan_error
    return UsageSnapshot(
        updated_at=datetime.now(timezone.utc),
        codex_quota=codex_quota,
        codex_today=codex_scan.today,
        codex_hourly=codex_scan.hourly,
    )


def _cache_age_seconds(now: datetime) -> float | None:
    if _cache is None or _cache_time is None:
        return None
    return (now - _cache_time).total_seconds()


def _force_refresh_age_seconds(now: datetime) -> float | None:
    if _cache is None or _last_force_refresh_time is None:
        return None
    return (now - _last_force_refresh_time).total_seconds()


async def get_snapshot_cached(*, force: bool = False) -> UsageSnapshot:
    global _cache, _cache_time, _last_force_refresh_time
    now = datetime.now(timezone.utc)
    age = _force_refresh_age_seconds(now) if force else _cache_age_seconds(now)
    max_age = FORCE_REFRESH_COALESCE_SECONDS if force else settings.cache_ttl_seconds
    if _cache and age is not None and age < max_age:
        return _cache
    async with _cache_lock:
        now = datetime.now(timezone.utc)
        age = _force_refresh_age_seconds(now) if force else _cache_age_seconds(now)
        max_age = FORCE_REFRESH_COALESCE_SECONDS if force else settings.cache_ttl_seconds
        if _cache and age is not None and age < max_age:
            return _cache
        _cache = await build_snapshot()
        _cache_time = datetime.now(timezone.utc)
        if force:
            _last_force_refresh_time = _cache_time
        return _cache


@app.get("/health")
async def health() -> dict[str, object]:
    return {
        "ok": True,
        "codex_home_exists": settings.codex_home.exists(),
        "requires_token": bool(settings.watch_token),
    }


@app.get("/usage", dependencies=[Depends(require_token)])
async def usage(force: Annotated[bool, Query()] = False) -> UsageSnapshot:
    return await get_snapshot_cached(force=force)


@app.get("/v1/snapshot", dependencies=[Depends(require_token)])
async def snapshot_v1(force: Annotated[bool, Query()] = False) -> dict[str, object]:
    return (await get_snapshot_cached(force=force)).snapshot()


@app.get("/watch", dependencies=[Depends(require_token)])
async def watch_compact(force: Annotated[bool, Query()] = False) -> dict[str, object]:
    return (await get_snapshot_cached(force=force)).compact()


def run() -> None:
    validate_runtime_settings()
    uvicorn.run("codex_watch_agent.main:app", host=settings.host, port=settings.port, reload=False)


if __name__ == "__main__":
    run()
