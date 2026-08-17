import importlib

import pytest
from fastapi import HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.testclient import TestClient

from codex_watch_agent.models import QuotaStatus, UsageSnapshot


VALID_WATCH_TOKEN = "valid_watch_token_1234567890"


def _reload_main(monkeypatch, watch_token: str | None):
    monkeypatch.setenv("PYTHON_DOTENV_DISABLED", "1")
    if watch_token is None:
        monkeypatch.delenv("WATCH_TOKEN", raising=False)
    else:
        monkeypatch.setenv("WATCH_TOKEN", watch_token)

    import codex_watch_agent.main as main_module
    import codex_watch_agent.settings as settings_module

    importlib.reload(settings_module)
    return importlib.reload(main_module)


@pytest.mark.parametrize(
    "watch_token",
    [None, "", "   ", "short-token", "invalid-token!", "change-me-to-a-long-random-token"],
)
def test_runtime_settings_rejects_missing_or_placeholder_watch_token(
    monkeypatch, watch_token: str | None
) -> None:
    main_module = _reload_main(monkeypatch, watch_token)

    with pytest.raises(RuntimeError, match="WATCH_TOKEN"):
        main_module.validate_runtime_settings()


def test_token_dependency_rejects_missing_server_token(monkeypatch) -> None:
    main_module = _reload_main(monkeypatch, None)

    with pytest.raises(HTTPException) as exc_info:
        main_module.require_token(None)

    assert exc_info.value.status_code == 500


def test_token_dependency_requires_matching_watch_token(monkeypatch) -> None:
    main_module = _reload_main(monkeypatch, VALID_WATCH_TOKEN)

    with pytest.raises(HTTPException) as exc_info:
        main_module.require_token("wrong-token")

    assert exc_info.value.status_code == 401
    assert main_module.require_token(VALID_WATCH_TOKEN) is None


def test_token_dependency_rejects_malformed_request_token(monkeypatch) -> None:
    main_module = _reload_main(monkeypatch, VALID_WATCH_TOKEN)

    with pytest.raises(HTTPException) as exc_info:
        main_module.require_token("invalid-token!")

    assert exc_info.value.status_code == 401


def test_agent_does_not_enable_wildcard_cors_by_default(monkeypatch) -> None:
    main_module = _reload_main(monkeypatch, VALID_WATCH_TOKEN)

    middleware_classes = [middleware.cls for middleware in main_module.app.user_middleware]

    assert CORSMiddleware not in middleware_classes


def test_v1_snapshot_route_returns_sanitized_snapshot(monkeypatch) -> None:
    main_module = _reload_main(monkeypatch, VALID_WATCH_TOKEN)
    snapshot = UsageSnapshot(codex_quota=QuotaStatus(provider="codex", label="Codex", status="ok"))

    async def fake_get_snapshot_cached(*, force: bool = False):
        return snapshot

    monkeypatch.setattr(main_module, "get_snapshot_cached", fake_get_snapshot_cached)

    with TestClient(main_module.app) as client:
        response = client.get("/v1/snapshot", headers={"x-watch-token": VALID_WATCH_TOKEN})

    assert response.status_code == 200
    body = response.json()
    assert body["schema_version"] == "v1"
    assert sorted(body["providers"]) == ["codex"]
