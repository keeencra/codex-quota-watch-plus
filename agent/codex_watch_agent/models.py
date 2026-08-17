from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Any, Literal

from pydantic import BaseModel, Field

MAX_ERROR_SUMMARY_LENGTH = 240


def safe_error_summary(error: str | None) -> str | None:
    if error is None:
        return None
    text = str(error).strip()
    if not text:
        return None
    text = re.sub(r"/Users/[^/\s]+", "~", text)
    text = re.sub(r"(https?://[^\s?]+)\?[^\s]+", r"\1?<redacted>", text)
    text = re.sub(
        r"(?i)\b(token|api[_-]?key|authorization|cookie|secret)([=:]\s*)[^\s&]+",
        r"\1\2<redacted>",
        text,
    )
    text = re.sub(r"(?i)\b(bearer\s+)[A-Za-z0-9._~+/\-=]+", r"\1<redacted>", text)
    if len(text) > MAX_ERROR_SUMMARY_LENGTH:
        text = text[: MAX_ERROR_SUMMARY_LENGTH - 3].rstrip() + "..."
    return text


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class TokenStats(BaseModel):
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    cache_creation_tokens: int = 0

    @property
    def cache_tokens(self) -> int:
        return self.cache_read_tokens + self.cache_creation_tokens

    @property
    def total_tokens(self) -> int:
        return self.input_tokens + self.output_tokens + self.cache_tokens


class HourBucket(BaseModel):
    hour: int = Field(ge=0, le=23)
    input_tokens: int = 0
    output_tokens: int = 0
    cache_tokens: int = 0
    total_tokens: int = 0


class QuotaBucket(BaseModel):
    id: str | None = None
    label: str | None = None
    remaining_percent: float | None = None
    used_percent: float | None = None
    reset_at: datetime | None = None
    reset_in: str | None = None
    window: str | None = None
    status: Literal["ok", "partial", "error", "not_configured"] = "partial"
    details: dict[str, Any] = Field(default_factory=dict)


class QuotaStatus(BaseModel):
    provider: Literal["codex", "openai_api"]
    label: str
    remaining_percent: float | None = None
    used_percent: float | None = None
    reset_at: datetime | None = None
    reset_in: str | None = None
    window: str | None = None
    source: str = "unknown"
    updated_at: datetime = Field(default_factory=utc_now)
    status: Literal["ok", "not_configured", "partial", "error"] = "not_configured"
    error: str | None = None
    buckets: list[QuotaBucket] = Field(default_factory=list)
    details: dict[str, Any] = Field(default_factory=dict)


class UsageSnapshot(BaseModel):
    updated_at: datetime = Field(default_factory=utc_now)
    codex_quota: QuotaStatus
    codex_today: TokenStats = Field(default_factory=TokenStats)
    codex_hourly: list[HourBucket] = Field(default_factory=list)

    def _hourly_compact(self, hourly: list[HourBucket]) -> list[dict[str, int]]:
        return [
            {
                "hour": bucket.hour,
                "tokens": bucket.total_tokens,
            }
            for bucket in hourly
        ]

    def _hourly_snapshot(self, hourly: list[HourBucket]) -> list[dict[str, int]]:
        return [
            {
                "hour": bucket.hour,
                "input_tokens": bucket.input_tokens,
                "output_tokens": bucket.output_tokens,
                "cache_tokens": bucket.cache_tokens,
                "total_tokens": bucket.total_tokens,
            }
            for bucket in hourly
        ]

    def _today_snapshot(self, today: TokenStats) -> dict[str, int]:
        return {
            "input_tokens": today.input_tokens,
            "output_tokens": today.output_tokens,
            "cache_tokens": today.cache_tokens,
            "total_tokens": today.total_tokens,
        }

    def _quota_snapshot(self, quota: QuotaStatus) -> dict[str, Any]:
        return {
            "label": quota.label,
            "remaining_percent": quota.remaining_percent,
            "used_percent": quota.used_percent,
            "reset_at": quota.reset_at.isoformat() if quota.reset_at else None,
            "reset_in": quota.reset_in,
            "window": quota.window,
            "source": quota.source,
            "updated_at": quota.updated_at.isoformat(),
            "status": quota.status,
            "error": safe_error_summary(quota.error),
            "buckets": [
                {
                    "id": bucket.id,
                    "label": bucket.label,
                    "remaining_percent": bucket.remaining_percent,
                    "used_percent": bucket.used_percent,
                    "reset_at": bucket.reset_at.isoformat() if bucket.reset_at else None,
                    "reset_in": bucket.reset_in,
                    "window": bucket.window,
                    "status": bucket.status,
                }
                for bucket in quota.buckets
            ],
        }

    def _provider_snapshot(
        self,
        quota: QuotaStatus,
        today: TokenStats,
        hourly: list[HourBucket],
    ) -> dict[str, Any]:
        return {
            "quota": self._quota_snapshot(quota),
            "today": self._today_snapshot(today),
            "hourly": self._hourly_snapshot(hourly),
        }

    def _provider_compact(
        self,
        quota: QuotaStatus,
        today: TokenStats,
        hourly: list[HourBucket],
    ) -> dict[str, Any]:
        return {
            "remaining_percent": quota.remaining_percent,
            "used_percent": quota.used_percent,
            "reset_in": quota.reset_in,
            "window": quota.window,
            "status": quota.status,
            "source": quota.source,
            "error": safe_error_summary(quota.error),
            "quota_updated_at": quota.updated_at.isoformat(),
            "today_tokens": today.total_tokens,
            "today_input_tokens": today.input_tokens,
            "today_output_tokens": today.output_tokens,
            "today_cache_tokens": today.cache_tokens,
            "hourly": self._hourly_compact(hourly),
            "buckets": [
                {
                    "id": bucket.id,
                    "label": bucket.label,
                    "remaining_percent": bucket.remaining_percent,
                    "used_percent": bucket.used_percent,
                    "reset_in": bucket.reset_in,
                    "window": bucket.window,
                    "status": bucket.status,
                }
                for bucket in quota.buckets
            ],
        }

    def snapshot(self) -> dict[str, Any]:
        return {
            "schema_version": "v1",
            "updated_at": self.updated_at.isoformat(),
            "stale": False,
            "providers": {
                "codex": self._provider_snapshot(
                    self.codex_quota,
                    self.codex_today,
                    self.codex_hourly,
                ),
            },
        }

    def compact(self) -> dict[str, Any]:
        return {
            "updated_at": self.updated_at.isoformat(),
            "codex": self._provider_compact(
                self.codex_quota,
                self.codex_today,
                self.codex_hourly,
            ),
        }
