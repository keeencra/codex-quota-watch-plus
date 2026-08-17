from __future__ import annotations

import asyncio
import json
import os
import shlex
import subprocess
import time
from datetime import datetime, timezone
from typing import Any

import httpx

from .codex_rpc import normalize_rate_limits_for_command, read_codex_rate_limits
from .models import QuotaBucket, QuotaStatus, TokenStats
from .quota_cache import read_quota_cache, write_quota_cache
from .settings import Settings


SENSITIVE_DETAIL_KEYS = {"token", "access_token", "auth", "authorization", "cookie", "api_key", "apikey", "secret"}
STALE_CODEX_CACHE_MAX_AGE_SECONDS = 24 * 60 * 60


def _parse_dt(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc)
    if isinstance(value, (int, float)):
        try:
            ts = value / 1000 if value > 10_000_000_000 else value
            return datetime.fromtimestamp(ts, tz=timezone.utc)
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
            return datetime.fromisoformat(s).astimezone(timezone.utc)
        except Exception:
            return None
    return None


def _human_reset_in(reset_at: datetime | None) -> str | None:
    if reset_at is None:
        return None
    seconds = int((reset_at - datetime.now(timezone.utc)).total_seconds())
    if seconds <= 0:
        return "now"
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def _window_label(mins: Any) -> str | None:
    try:
        value = int(mins)
    except Exception:
        return None
    if value % (24 * 60) == 0:
        return f"{value // (24 * 60)}d"
    if value % 60 == 0:
        return f"{value // 60}h"
    return f"{value}m"


def _coerce_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except Exception:
        return None


def _first_present(*values: Any) -> Any:
    for value in values:
        if value is not None:
            return value
    return None


def _safe_details(payload: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for k, v in payload.items():
        lk = str(k).lower()
        if any(s in lk for s in SENSITIVE_DETAIL_KEYS):
            continue
        # Keep details small enough for watch sync.
        if isinstance(v, (dict, list)):
            try:
                text = json.dumps(v, ensure_ascii=False)
            except Exception:
                continue
            if len(text) <= 1200:
                out[k] = v
        else:
            out[k] = v
    return out


def _bucket_from_generic(raw: dict[str, Any], index: int) -> QuotaBucket:
    reset_at = _parse_dt(raw.get("reset_at") or raw.get("resets_at") or raw.get("resetAt") or raw.get("resetsAt"))
    remaining = _coerce_float(
        _first_present(raw.get("remaining_percent"), raw.get("remainingPercent"), raw.get("remainingPct"))
    )
    used = _coerce_float(_first_present(raw.get("used_percent"), raw.get("usedPercent"), raw.get("usedPct")))
    if remaining is None and used is not None:
        remaining = max(0.0, min(100.0, 100.0 - used))
    if used is None and remaining is not None:
        used = max(0.0, min(100.0, 100.0 - remaining))
    status = raw.get("status") or ("ok" if remaining is not None or used is not None or reset_at else "partial")
    if status not in {"ok", "partial", "error", "not_configured"}:
        status = "partial"
    return QuotaBucket(
        id=str(raw.get("id") or raw.get("limit_id") or raw.get("limitId") or index),
        label=str(raw.get("label") or raw.get("name") or raw.get("limitName") or raw.get("window") or f"bucket {index + 1}"),
        remaining_percent=remaining,
        used_percent=used,
        reset_at=reset_at,
        reset_in=raw.get("reset_in") or raw.get("resetIn") or _human_reset_in(reset_at),
        window=str(raw.get("window")) if raw.get("window") else None,
        status=status,  # type: ignore[arg-type]
        details=_safe_details(raw.get("details") if isinstance(raw.get("details"), dict) else raw),
    )


def _choose_main_bucket(buckets: list[QuotaBucket]) -> QuotaBucket | None:
    ok = [b for b in buckets if b.remaining_percent is not None]
    if ok:
        return min(ok, key=lambda b: float(b.remaining_percent if b.remaining_percent is not None else 101.0))
    return buckets[0] if buckets else None


def _normalize_quota(provider: str, label: str, source: str, payload: dict[str, Any]) -> QuotaStatus:
    buckets: list[QuotaBucket] = []
    raw_buckets = payload.get("buckets")
    if isinstance(raw_buckets, list):
        buckets = [_bucket_from_generic(b, i) for i, b in enumerate(raw_buckets) if isinstance(b, dict)]

    # Accept a few common shapes so user can plug a curl command without changing code.
    remaining = _first_present(
        payload.get("remaining_percent"),
        payload.get("remainingPercent"),
        payload.get("remainingPct"),
        payload.get("remaining"),
    )
    used = _first_present(payload.get("used_percent"), payload.get("usedPercent"), payload.get("usedPct"))

    limit = _coerce_float(payload.get("limit") or payload.get("quota") or payload.get("total"))
    used_value = _coerce_float(payload.get("used"))
    remaining_value = _coerce_float(_first_present(payload.get("remaining_value"), payload.get("remaining_units")))

    remaining_f = _coerce_float(remaining)
    used_f = _coerce_float(used)
    if remaining_f is None and limit and remaining_value is not None:
        remaining_f = max(0.0, min(100.0, remaining_value / limit * 100.0))
    if remaining_f is None and limit and used_value is not None:
        remaining_f = max(0.0, min(100.0, 100.0 - used_value / limit * 100.0))
    if used_f is None and remaining_f is not None:
        used_f = 100.0 - remaining_f
    if remaining_f is None and buckets:
        main = _choose_main_bucket(buckets)
        if main:
            remaining_f = main.remaining_percent
            used_f = main.used_percent

    reset_at = _parse_dt(payload.get("reset_at") or payload.get("resets_at") or payload.get("resetTime") or payload.get("resetAt"))
    reset_in = payload.get("reset_in") or payload.get("resetIn") or _human_reset_in(reset_at)
    if reset_at is None and buckets:
        main = _choose_main_bucket(buckets)
        if main:
            reset_at = main.reset_at
            reset_in = reset_in or main.reset_in

    window = str(payload.get("window")) if payload.get("window") else None
    if window is None and buckets:
        main = _choose_main_bucket(buckets)
        window = main.window if main else None

    raw_status = payload.get("status")
    if raw_status in {"ok", "not_configured", "partial", "error"}:
        status = raw_status
    else:
        status = "ok" if remaining_f is not None or reset_in else "partial"

    return QuotaStatus(
        provider=provider,  # type: ignore[arg-type]
        label=label,
        remaining_percent=remaining_f,
        used_percent=used_f,
        reset_at=reset_at,
        reset_in=reset_in,
        window=window,
        source=source,
        status=status,  # type: ignore[arg-type]
        buckets=buckets,
        details=_safe_details(payload),
    )


def _normalize_codex_app_server(payload: dict[str, Any]) -> QuotaStatus:
    by_id = payload.get("rateLimitsByLimitId")
    if not isinstance(by_id, dict):
        single = payload.get("rateLimits")
        by_id = {single.get("limitId", "codex"): single} if isinstance(single, dict) else {}

    buckets: list[QuotaBucket] = []
    for limit_id, raw_bucket in by_id.items():
        if not isinstance(raw_bucket, dict):
            continue
        for slot_name in ("primary", "secondary"):
            slot = raw_bucket.get(slot_name)
            if not isinstance(slot, dict):
                continue
            used = _coerce_float(_first_present(slot.get("usedPercent"), slot.get("used_percentage")))
            remaining = None if used is None else max(0.0, min(100.0, 100.0 - used))
            reset_at = _parse_dt(slot.get("resetsAt") or slot.get("resetAt") or slot.get("reset_at"))
            window = _window_label(slot.get("windowDurationMins") or slot.get("window_duration_mins"))
            label_bits = [str(raw_bucket.get("limitName") or limit_id)]
            if window:
                label_bits.append(window)
            if slot_name == "secondary":
                label_bits.append("secondary")
            buckets.append(
                QuotaBucket(
                    id=f"{limit_id}:{slot_name}",
                    label=" ".join(label_bits),
                    remaining_percent=remaining,
                    used_percent=used,
                    reset_at=reset_at,
                    reset_in=_human_reset_in(reset_at),
                    window=window,
                    status="ok" if used is not None or reset_at else "partial",
                    details={
                        "limit_id": limit_id,
                        "rate_limit_reached_type": raw_bucket.get("rateLimitReachedType"),
                        "plan_type": raw_bucket.get("planType"),
                        "credits": raw_bucket.get("credits"),
                    },
                )
            )

    main = _choose_main_bucket(buckets)
    status = "ok" if buckets else "partial"
    return QuotaStatus(
        provider="codex",
        label="Codex",
        remaining_percent=main.remaining_percent if main else None,
        used_percent=main.used_percent if main else None,
        reset_at=main.reset_at if main else None,
        reset_in=main.reset_in if main else None,
        window=main.window if main else None,
        source="codex app-server account/rateLimits/read",
        status=status,  # type: ignore[arg-type]
        buckets=buckets,
        details={"raw_keys": sorted(payload.keys())},
    )


def _codex_command_timeouts(settings: Settings) -> tuple[int, int]:
    provider_timeout = max(1, int(settings.quota_provider_timeout_seconds))
    app_server_timeout = max(1, int(settings.codex_app_server_timeout_seconds))
    capped_app_server_timeout = min(app_server_timeout, max(1, provider_timeout - 4))
    command_timeout = min(max(capped_app_server_timeout + 2, 1), max(1, provider_timeout - 1))
    return capped_app_server_timeout, command_timeout


def _codex_command_env(settings: Settings, *, app_server_timeout_seconds: int | None = None) -> dict[str, str]:
    env = os.environ.copy()
    env["CODEX_BINARY"] = settings.codex_binary
    env["CODEX_APP_SERVER_TIMEOUT_SECONDS"] = str(app_server_timeout_seconds or settings.codex_app_server_timeout_seconds)
    return env


def _run_json_command(command: str, *, timeout: int = 20, env: dict[str, str] | None = None) -> dict[str, Any]:
    proc = subprocess.run(
        command,
        shell=True,
        cwd=os.path.expanduser("~"),
        text=True,
        capture_output=True,
        timeout=timeout,
        env=env,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or f"command failed with code {proc.returncode}")
    stdout = proc.stdout.strip()
    if not stdout:
        raise RuntimeError("command produced empty output")
    return json.loads(stdout)


def _is_builtin_codex_app_server_command(command: str) -> bool:
    try:
        parts = shlex.split(command)
    except ValueError:
        return False
    if not parts:
        return False
    return os.path.basename(parts[0]) == "codex-quota-app-server" and "--raw" not in parts


def cached_codex_quota(settings: Settings, source: str, *, allow_stale: bool = False) -> QuotaStatus | None:
    cached = read_quota_cache(
        provider="codex",
        max_age_seconds=STALE_CODEX_CACHE_MAX_AGE_SECONDS if allow_stale else settings.quota_cache_max_age_seconds,
        cache_path=settings.codex_quota_cache_path,
    )
    if cached is None:
        return None
    payload, cache_details = cached
    quota = _normalize_quota("codex", "Codex", source, payload)
    if "CODEX_QUOTA_COMMAND" in source and "cache" in source and not (quota.buckets or quota.window or quota.reset_in):
        return None
    details = dict(quota.details)
    details.update(cache_details)
    if allow_stale and cache_details.get("cache_age_seconds", 0) > settings.quota_cache_max_age_seconds:
        details["cache_stale"] = True
    update: dict[str, Any] = {"source": source, "details": details}
    cached_at = cache_details.get("cache_cached_at")
    if isinstance(cached_at, (int, float)):
        update["updated_at"] = datetime.fromtimestamp(float(cached_at), tz=timezone.utc)
    return quota.model_copy(update=update)


async def _fetch_json(url: str, *, bearer_token: str | None = None, headers: dict[str, str] | None = None) -> dict[str, Any]:
    request_headers = dict(headers or {})
    if bearer_token:
        request_headers["Authorization"] = f"Bearer {bearer_token}"
    async with httpx.AsyncClient(timeout=12) as client:
        resp = await client.get(url, headers=request_headers)
        resp.raise_for_status()
        return resp.json()


async def get_codex_quota(settings: Settings) -> QuotaStatus:
    if settings.codex_quota_command:
        try:
            app_server_timeout, command_timeout = _codex_command_timeouts(settings)
            if _is_builtin_codex_app_server_command(settings.codex_quota_command):
                raw_payload = await asyncio.to_thread(
                    read_codex_rate_limits,
                    codex_binary=settings.codex_binary,
                    timeout_seconds=app_server_timeout,
                )
                payload = normalize_rate_limits_for_command(raw_payload)
                write_quota_cache(
                    provider="codex",
                    payload=payload,
                    source="codex app-server account/rateLimits/read",
                    cache_path=settings.codex_quota_cache_path,
                )
                return _normalize_quota("codex", "Codex", "codex app-server account/rateLimits/read", payload)
            payload = await asyncio.to_thread(
                _run_json_command,
                settings.codex_quota_command,
                timeout=command_timeout,
                env=_codex_command_env(settings, app_server_timeout_seconds=app_server_timeout),
            )
            write_quota_cache(
                provider="codex",
                payload=payload,
                source="CODEX_QUOTA_COMMAND",
                cache_path=settings.codex_quota_cache_path,
            )
            return _normalize_quota("codex", "Codex", "CODEX_QUOTA_COMMAND", payload)
        except Exception as exc:
            cached = cached_codex_quota(settings, "CODEX_QUOTA_COMMAND cache")
            if cached is None:
                cached = cached_codex_quota(settings, "CODEX_QUOTA_COMMAND stale cache", allow_stale=True)
            if cached is not None:
                return cached
            return QuotaStatus(provider="codex", label="Codex", status="error", error=str(exc), source="CODEX_QUOTA_COMMAND")

    if settings.codex_quota_url:
        try:
            payload = await _fetch_json(settings.codex_quota_url, bearer_token=settings.codex_quota_bearer_token)
            return _normalize_quota("codex", "Codex", "CODEX_QUOTA_URL", payload)
        except Exception as exc:
            return QuotaStatus(provider="codex", label="Codex", status="error", error=str(exc), source="CODEX_QUOTA_URL")

    if settings.codex_app_server_enabled:
        try:
            payload = read_codex_rate_limits(
                codex_binary=settings.codex_binary,
                timeout_seconds=settings.codex_app_server_timeout_seconds,
            )
            return _normalize_codex_app_server(payload)
        except Exception as exc:
            # Keep falling through to admin API only if configured. Otherwise report the
            # app-server error, because that is the exact personal quota path.
            if not settings.openai_admin_key:
                return QuotaStatus(
                    provider="codex",
                    label="Codex",
                    status="error",
                    source="codex app-server account/rateLimits/read",
                    error=str(exc),
                    details={"hint": "Confirm `codex app-server` works and that Codex is logged into ChatGPT."},
                )

    if settings.openai_admin_key:
        # Official OpenAI Usage API is for API usage monitoring. It is not the same as a
        # personal ChatGPT/Codex subscription quota, so we report partial data only.
        now = int(time.time())
        start = now - 24 * 60 * 60
        url = "https://api.openai.com/v1/organization/usage/completions"
        try:
            payload = await _fetch_json(
                f"{url}?start_time={start}&end_time={now}&bucket_width=1h&limit=24",
                bearer_token=settings.openai_admin_key,
            )
            totals = TokenStats()
            for bucket in payload.get("data", []):
                for result in bucket.get("results", []):
                    totals.input_tokens += int(result.get("input_tokens") or 0)
                    totals.output_tokens += int(result.get("output_tokens") or 0)
                    totals.cache_read_tokens += int(result.get("input_cached_tokens") or 0)
            return QuotaStatus(
                provider="codex",
                label="Codex/API",
                status="partial",
                source="OPENAI_ADMIN_KEY usage_api",
                details={
                    "note": "OpenAI Admin Usage API is API usage data, not ChatGPT/Codex subscription remaining quota.",
                    "last_24h_total_tokens": totals.total_tokens,
                    "last_24h_input_tokens": totals.input_tokens,
                    "last_24h_output_tokens": totals.output_tokens,
                    "last_24h_cached_tokens": totals.cache_read_tokens,
                },
            )
        except Exception as exc:
            return QuotaStatus(provider="codex", label="Codex/API", status="error", source="OPENAI_ADMIN_KEY usage_api", error=str(exc))

    return QuotaStatus(
        provider="codex",
        label="Codex",
        status="not_configured",
        source="none",
        details={
            "hint": "Default is codex app-server. If it fails, set CODEX_QUOTA_COMMAND or CODEX_QUOTA_URL. OPENAI_ADMIN_KEY can show API usage but not personal subscription quota."
        },
    )
