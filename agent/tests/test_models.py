from datetime import datetime, timezone

from codex_watch_agent.models import HourBucket, QuotaStatus, TokenStats, UsageSnapshot


def test_quota_status_updated_at_is_timezone_aware() -> None:
    quota = QuotaStatus(provider="codex", label="Codex")

    assert quota.updated_at.tzinfo is not None


def test_compact_includes_provider_quota_updated_at() -> None:
    quota = QuotaStatus(provider="codex", label="Codex", status="ok")
    snapshot = UsageSnapshot(codex_quota=quota)

    compact = snapshot.compact()

    assert compact["codex"]["quota_updated_at"] == quota.updated_at.isoformat()


def test_compact_includes_provider_error_summary() -> None:
    quota = QuotaStatus(provider="codex", label="Codex", status="error", source="scanner", error="failed to scan")
    snapshot = UsageSnapshot(codex_quota=quota)

    compact = snapshot.compact()

    assert compact["codex"]["error"] == "failed to scan"


def test_snapshot_outputs_redact_sensitive_error_fragments() -> None:
    user_path = "/Users/" + "alice/.codex/session.json"
    sensitive_key = "token"
    sensitive_value = "redact-me-123"
    quota = QuotaStatus(
        provider="codex",
        label="Codex",
        status="error",
        source="CODEX_QUOTA_URL",
        error=f"failed {user_path} {sensitive_key}={sensitive_value} "
        f"https://agent.local/watch?{sensitive_key}={sensitive_value}",
    )
    snapshot = UsageSnapshot(codex_quota=quota)

    compact_error = snapshot.compact()["codex"]["error"]
    snapshot_error = snapshot.snapshot()["providers"]["codex"]["quota"]["error"]

    assert user_path not in compact_error
    assert sensitive_value not in compact_error
    assert compact_error == snapshot_error


def test_compact_includes_hourly_heatmap() -> None:
    snapshot = UsageSnapshot(
        codex_quota=QuotaStatus(provider="codex", label="Codex"),
        codex_hourly=[
            HourBucket(hour=0, input_tokens=1, output_tokens=2, cache_tokens=3, total_tokens=6),
            HourBucket(hour=1, input_tokens=10, output_tokens=20, cache_tokens=30, total_tokens=60),
        ],
    )

    compact = snapshot.compact()

    assert compact["codex"]["hourly"] == [
        {"hour": 0, "tokens": 6},
        {"hour": 1, "tokens": 60},
    ]


def test_snapshot_payload_groups_providers_without_session_preview() -> None:
    updated_at = datetime(2026, 6, 12, 12, 0, tzinfo=timezone.utc)
    snapshot = UsageSnapshot(
        updated_at=updated_at,
        codex_quota=QuotaStatus(provider="codex", label="Codex", remaining_percent=72, status="ok"),
        codex_today=TokenStats(input_tokens=100, output_tokens=50, cache_read_tokens=25),
        codex_hourly=[HourBucket(hour=12, total_tokens=175)],
    )

    payload = snapshot.snapshot()

    assert payload["schema_version"] == "v1"
    assert payload["stale"] is False
    assert sorted(payload["providers"]) == ["codex"]
    assert payload["providers"]["codex"]["quota"]["remaining_percent"] == 72
    assert payload["providers"]["codex"]["today"]["total_tokens"] == 175
    assert payload["providers"]["codex"]["hourly"] == [
        {
            "hour": 12,
            "input_tokens": 0,
            "output_tokens": 0,
            "cache_tokens": 0,
            "total_tokens": 175,
        }
    ]
    assert "active_session" not in payload["providers"]["codex"]
