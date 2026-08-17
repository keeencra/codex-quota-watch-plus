import pytest
import json
import time
import asyncio

from codex_watch_agent.models import HourBucket, QuotaStatus, TokenStats
from codex_watch_agent.quota_cache import write_quota_cache
from codex_watch_agent.scanner import ScanResult


@pytest.mark.anyio
async def test_build_snapshot_keeps_working_when_one_quota_provider_raises(monkeypatch) -> None:
    import codex_watch_agent.main as main_module

    def fake_scan_usage_dir(*args, **kwargs):
        return ScanResult(today=TokenStats(input_tokens=1), hourly=[HourBucket(hour=1, total_tokens=1)])

    async def broken_codex_quota(settings):
        raise RuntimeError("codex quota crashed")

    monkeypatch.setattr(main_module, "scan_usage_dir", fake_scan_usage_dir)
    monkeypatch.setattr(main_module, "get_codex_quota", broken_codex_quota)

    snapshot = await main_module.build_snapshot()

    assert snapshot.codex_quota.status == "error"
    assert snapshot.codex_quota.source == "internal"
    assert "codex quota crashed" in (snapshot.codex_quota.error or "")
    assert snapshot.codex_today.total_tokens == 1


@pytest.mark.anyio
async def test_build_snapshot_keeps_working_when_one_scanner_raises(monkeypatch) -> None:
    import codex_watch_agent.main as main_module

    def flaky_scan_usage_dir(*args, **kwargs):
        raise RuntimeError("codex scan crashed")

    async def ok_codex_quota(settings):
        return QuotaStatus(provider="codex", label="Codex", status="ok", source="test")

    monkeypatch.setattr(main_module, "scan_usage_dir", flaky_scan_usage_dir)
    monkeypatch.setattr(main_module, "get_codex_quota", ok_codex_quota)

    snapshot = await main_module.build_snapshot()

    assert snapshot.codex_quota.status == "error"
    assert snapshot.codex_quota.source == "scanner"
    assert "codex scan crashed" in (snapshot.codex_quota.error or "")
    assert snapshot.codex_today.total_tokens == 0


@pytest.mark.anyio
async def test_build_snapshot_runs_scans_and_quota_providers_concurrently(monkeypatch) -> None:
    import codex_watch_agent.main as main_module

    def slow_scan_usage_dir(*args, **kwargs):
        time.sleep(0.15)
        return ScanResult(today=TokenStats(input_tokens=1), hourly=[])

    async def slow_codex_quota(settings):
        await asyncio.sleep(0.15)
        return QuotaStatus(provider="codex", label="Codex", status="ok", source="test")

    monkeypatch.setattr(main_module, "scan_usage_dir", slow_scan_usage_dir)
    monkeypatch.setattr(main_module, "get_codex_quota", slow_codex_quota)

    started = time.monotonic()
    snapshot = await main_module.build_snapshot()

    assert time.monotonic() - started < 0.3
    assert snapshot.codex_quota.status == "ok"
    assert snapshot.codex_today.total_tokens == 1


@pytest.mark.anyio
async def test_force_refresh_bypasses_regular_cache_but_coalesces_nearby_requests(monkeypatch) -> None:
    import codex_watch_agent.main as main_module

    calls = 0

    async def fake_build_snapshot():
        nonlocal calls
        calls += 1
        return main_module.UsageSnapshot(
            codex_quota=QuotaStatus(
                provider="codex",
                label="Codex",
                status="ok",
                source=f"test-{calls}",
                remaining_percent=100 - calls,
            )
        )

    monkeypatch.setattr(main_module, "_cache", None)
    monkeypatch.setattr(main_module, "_cache_time", None)
    monkeypatch.setattr(main_module, "_last_force_refresh_time", None)
    monkeypatch.setattr(main_module.settings, "cache_ttl_seconds", 60)
    monkeypatch.setattr(main_module, "build_snapshot", fake_build_snapshot)

    first = await main_module.get_snapshot_cached()
    cached = await main_module.get_snapshot_cached()
    forced = await main_module.get_snapshot_cached(force=True)
    coalesced = await main_module.get_snapshot_cached(force=True)

    assert first.codex_quota.remaining_percent == 99
    assert cached.codex_quota.remaining_percent == 99
    assert forced.codex_quota.remaining_percent == 98
    assert coalesced.codex_quota.remaining_percent == 98
    assert calls == 2


@pytest.mark.anyio
async def test_snapshot_errors_redact_local_usage_paths(monkeypatch) -> None:
    import codex_watch_agent.main as main_module

    leaked_path = main_module.settings.codex_home / "sessions" / "private.jsonl"

    def flaky_scan_usage_dir(root, *args, **kwargs):
        if root == main_module.settings.codex_home:
            raise RuntimeError(f"failed to read {leaked_path}")
        return ScanResult(today=TokenStats(), hourly=[])

    async def ok_codex_quota(settings):
        return QuotaStatus(provider="codex", label="Codex", status="ok", source="test")

    monkeypatch.setattr(main_module, "scan_usage_dir", flaky_scan_usage_dir)
    monkeypatch.setattr(main_module, "get_codex_quota", ok_codex_quota)

    snapshot = await main_module.build_snapshot()

    error = snapshot.codex_quota.error or ""
    assert str(main_module.settings.codex_home) not in error
    assert "<codex_home>" in error


@pytest.mark.anyio
async def test_safe_quota_times_out_blocking_provider(tmp_path, monkeypatch) -> None:
    import codex_watch_agent.main as main_module

    monkeypatch.setattr(main_module.settings, "quota_provider_timeout_seconds", 0.05)
    monkeypatch.setattr(main_module.settings, "codex_quota_cache_path", str(tmp_path / "missing-cache.json"))

    async def blocking_provider(settings):
        time.sleep(0.3)
        return QuotaStatus(provider="codex", label="Codex", status="ok", source="too-late")

    started = time.monotonic()
    quota = await main_module._safe_quota("codex", blocking_provider)

    assert time.monotonic() - started < 0.25
    assert quota.status == "error"
    assert quota.source == "internal"
    assert "timed out" in (quota.error or "").lower()


@pytest.mark.anyio
async def test_safe_quota_uses_codex_cache_after_provider_timeout(tmp_path, monkeypatch) -> None:
    import codex_watch_agent.main as main_module

    cache_path = tmp_path / "codex-cache.json"
    write_quota_cache(
        provider="codex",
        payload={
            "status": "ok",
            "remaining_percent": 58,
            "used_percent": 42,
            "reset_in": "2h 10m",
            "window": "5h",
        },
        source="test",
        cache_path=cache_path,
    )
    monkeypatch.setattr(main_module.settings, "quota_provider_timeout_seconds", 0.05)
    monkeypatch.setattr(main_module.settings, "codex_quota_cache_path", str(cache_path))
    monkeypatch.setattr(main_module.settings, "quota_cache_max_age_seconds", 300)

    async def blocking_provider(settings):
        time.sleep(0.3)
        return QuotaStatus(provider="codex", label="Codex", status="ok", source="too-late")

    quota = await main_module._safe_quota("codex", blocking_provider)

    assert quota.status == "ok"
    assert quota.source == "CODEX_QUOTA_COMMAND cache"
    assert quota.remaining_percent == 58


@pytest.mark.anyio
async def test_safe_quota_uses_stale_codex_cache_after_provider_timeout(tmp_path, monkeypatch) -> None:
    import codex_watch_agent.main as main_module

    cache_path = tmp_path / "codex-cache.json"
    write_quota_cache(
        provider="codex",
        payload={
            "status": "ok",
            "remaining_percent": 47,
            "used_percent": 53,
            "reset_in": "2h 10m",
            "window": "5h",
            "buckets": [
                {
                    "id": "codex:primary",
                    "label": "Codex 5h",
                    "remaining_percent": 47,
                    "used_percent": 53,
                    "reset_in": "2h 10m",
                    "window": "5h",
                    "status": "ok",
                }
            ],
        },
        source="test",
        cache_path=cache_path,
    )
    raw = json.loads(cache_path.read_text())
    raw["cached_at"] = time.time() - 3600
    cache_path.write_text(json.dumps(raw))
    monkeypatch.setattr(main_module.settings, "quota_provider_timeout_seconds", 0.05)
    monkeypatch.setattr(main_module.settings, "codex_quota_cache_path", str(cache_path))
    monkeypatch.setattr(main_module.settings, "quota_cache_max_age_seconds", 300)

    async def blocking_provider(settings):
        time.sleep(0.3)
        return QuotaStatus(provider="codex", label="Codex", status="ok", source="too-late")

    quota = await main_module._safe_quota("codex", blocking_provider)

    assert quota.status == "ok"
    assert quota.source == "CODEX_QUOTA_COMMAND stale cache"
    assert quota.remaining_percent == 47
    assert quota.details["cache_stale"] is True
