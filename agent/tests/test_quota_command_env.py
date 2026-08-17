import json
import sys
import time
from datetime import datetime, timezone

import pytest

from codex_watch_agent.quota import get_codex_quota
from codex_watch_agent.quota_cache import write_quota_cache
from codex_watch_agent.settings import Settings


@pytest.mark.anyio
async def test_codex_quota_command_caps_codex_app_server_timeout_below_provider_timeout(tmp_path, monkeypatch) -> None:
    monkeypatch.delenv("CODEX_BINARY", raising=False)
    monkeypatch.delenv("CODEX_APP_SERVER_TIMEOUT_SECONDS", raising=False)

    command = tmp_path / "quota_command.py"
    command.write_text(
        "import json, os\n"
        "print(json.dumps({\n"
        "    'status': 'ok',\n"
        "    'remaining_percent': 42,\n"
        "    'details': {\n"
        "        'codex_binary': os.environ.get('CODEX_BINARY'),\n"
        "        'timeout': os.environ.get('CODEX_APP_SERVER_TIMEOUT_SECONDS'),\n"
        "    },\n"
        "}))\n"
    )

    settings = Settings(
        codex_quota_command=f"{sys.executable} {command}",
        codex_quota_cache_path=str(tmp_path / "codex-cache.json"),
        codex_binary="/opt/homebrew/bin/codex",
        codex_app_server_timeout_seconds=30,
        quota_provider_timeout_seconds=16,
    )

    quota = await get_codex_quota(settings)

    assert quota.status == "ok"
    assert quota.remaining_percent == 42
    assert quota.details["details"]["codex_binary"] == "/opt/homebrew/bin/codex"
    assert quota.details["details"]["timeout"] == "12"


@pytest.mark.anyio
async def test_codex_quota_command_keeps_requested_timeout_when_provider_allows(tmp_path, monkeypatch) -> None:
    monkeypatch.delenv("CODEX_APP_SERVER_TIMEOUT_SECONDS", raising=False)

    command = tmp_path / "quota_command.py"
    command.write_text(
        "import json, os\n"
        "print(json.dumps({\n"
        "    'status': 'ok',\n"
        "    'remaining_percent': 42,\n"
        "    'details': {'timeout': os.environ.get('CODEX_APP_SERVER_TIMEOUT_SECONDS')},\n"
        "}))\n"
    )

    settings = Settings(
        codex_quota_command=f"{sys.executable} {command}",
        codex_quota_cache_path=str(tmp_path / "codex-cache.json"),
        codex_app_server_timeout_seconds=30,
        quota_provider_timeout_seconds=40,
    )

    quota = await get_codex_quota(settings)

    assert quota.status == "ok"
    assert quota.details["details"]["timeout"] == "30"


@pytest.mark.anyio
async def test_codex_quota_command_uses_recent_cache_after_command_failure(tmp_path) -> None:
    cache_path = tmp_path / "codex-cache.json"
    write_quota_cache(
        provider="codex",
        payload={
            "status": "ok",
            "remaining_percent": 64,
            "used_percent": 36,
            "reset_in": "2h 10m",
            "window": "5h",
        },
        source="test",
        cache_path=cache_path,
    )
    expected_cached_at = datetime.fromtimestamp(time.time() - 60, tz=timezone.utc)
    raw = json.loads(cache_path.read_text())
    raw["cached_at"] = expected_cached_at.timestamp()
    cache_path.write_text(json.dumps(raw))
    settings = Settings(
        codex_quota_command=f"{sys.executable} -c 'raise SystemExit(2)'",
        codex_quota_cache_path=str(cache_path),
        quota_cache_max_age_seconds=300,
    )

    quota = await get_codex_quota(settings)

    assert quota.status == "ok"
    assert quota.remaining_percent == 64
    assert quota.source == "CODEX_QUOTA_COMMAND cache"
    assert quota.details["cache_source"] == "test"
    assert quota.updated_at == expected_cached_at


@pytest.mark.anyio
async def test_codex_quota_command_uses_in_process_adapter_for_builtin_app_server(tmp_path, monkeypatch) -> None:
    def fail_shell_command(*args, **kwargs):  # noqa: ANN002, ANN003
        raise AssertionError("builtin codex-quota-app-server should not be launched as a shell command")

    def fake_rate_limits(*, codex_binary: str, timeout_seconds: int) -> dict:
        return {
            "rateLimitsByLimitId": {
                "codex": {
                    "limitName": "codex",
                    "primary": {
                        "usedPercent": 24,
                        "windowDurationMins": 300,
                        "resetsAt": "2026-06-12T15:00:00Z",
                    },
                    "secondary": {
                        "usedPercent": 82,
                        "windowDurationMins": 10080,
                        "resetsAt": "2026-06-14T18:00:00Z",
                    },
                }
            }
        }

    monkeypatch.setattr("codex_watch_agent.quota._run_json_command", fail_shell_command)
    monkeypatch.setattr("codex_watch_agent.quota.read_codex_rate_limits", fake_rate_limits)
    settings = Settings(
        codex_quota_command=str(tmp_path / "bin" / "codex-quota-app-server"),
        codex_quota_cache_path=str(tmp_path / "codex-cache.json"),
        codex_binary="/opt/homebrew/bin/codex",
        codex_app_server_timeout_seconds=12,
        quota_provider_timeout_seconds=16,
    )

    quota = await get_codex_quota(settings)

    assert quota.status == "ok"
    assert quota.source == "codex app-server account/rateLimits/read"
    assert quota.remaining_percent == 18
    raw_cache = json.loads((tmp_path / "codex-cache.json").read_text())
    assert raw_cache["source"] == "codex app-server account/rateLimits/read"
    assert raw_cache["payload"]["buckets"][0]["id"] == "codex:primary"


@pytest.mark.anyio
async def test_codex_quota_command_uses_stale_complete_cache_after_command_failure(tmp_path) -> None:
    cache_path = tmp_path / "codex-cache.json"
    write_quota_cache(
        provider="codex",
        payload={
            "status": "ok",
            "remaining_percent": 52,
            "used_percent": 48,
            "reset_in": "1h 5m",
            "window": "5h",
            "buckets": [
                {
                    "id": "codex:primary",
                    "label": "Codex 5h",
                    "remaining_percent": 52,
                    "used_percent": 48,
                    "reset_in": "1h 5m",
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
    settings = Settings(
        codex_quota_command=f"{sys.executable} -c 'raise SystemExit(2)'",
        codex_quota_cache_path=str(cache_path),
        quota_cache_max_age_seconds=300,
    )

    quota = await get_codex_quota(settings)

    assert quota.status == "ok"
    assert quota.remaining_percent == 52
    assert quota.source == "CODEX_QUOTA_COMMAND stale cache"
    assert quota.details["cache_stale"] is True


@pytest.mark.anyio
async def test_codex_quota_command_rejects_day_old_stale_cache_after_command_failure(tmp_path) -> None:
    cache_path = tmp_path / "codex-cache.json"
    write_quota_cache(
        provider="codex",
        payload={
            "status": "ok",
            "remaining_percent": 52,
            "reset_in": "1h 5m",
            "window": "5h",
        },
        source="test",
        cache_path=cache_path,
    )
    raw = json.loads(cache_path.read_text())
    raw["cached_at"] = time.time() - (25 * 60 * 60)
    cache_path.write_text(json.dumps(raw))
    settings = Settings(
        codex_quota_command=f"{sys.executable} -c 'raise SystemExit(2)'",
        codex_quota_cache_path=str(cache_path),
        quota_cache_max_age_seconds=300,
    )

    quota = await get_codex_quota(settings)

    assert quota.status == "error"
    assert quota.source == "CODEX_QUOTA_COMMAND"


@pytest.mark.anyio
async def test_codex_quota_command_rejects_degraded_percent_only_cache_after_failure(tmp_path) -> None:
    cache_path = tmp_path / "codex-cache.json"
    write_quota_cache(
        provider="codex",
        payload={
            "status": "ok",
            "remaining_percent": 42,
            "details": {"note": "legacy percent-only cache"},
        },
        source="test",
        cache_path=cache_path,
    )
    settings = Settings(
        codex_quota_command=f"{sys.executable} -c 'raise SystemExit(2)'",
        codex_quota_cache_path=str(cache_path),
        quota_cache_max_age_seconds=300,
    )

    quota = await get_codex_quota(settings)

    assert quota.status == "error"
    assert quota.source == "CODEX_QUOTA_COMMAND"
    assert "command failed" in (quota.error or "")
