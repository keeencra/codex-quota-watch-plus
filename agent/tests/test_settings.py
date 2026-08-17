import importlib


def test_agent_host_defaults_to_loopback(monkeypatch) -> None:
    monkeypatch.setenv("PYTHON_DOTENV_DISABLED", "1")
    monkeypatch.delenv("AGENT_HOST", raising=False)

    import codex_watch_agent.settings as settings_module

    reloaded = importlib.reload(settings_module)

    assert reloaded.Settings().host == "127.0.0.1"


def test_agent_cache_ttl_defaults_to_sixty_seconds(monkeypatch) -> None:
    monkeypatch.setenv("PYTHON_DOTENV_DISABLED", "1")
    monkeypatch.delenv("CACHE_TTL_SECONDS", raising=False)

    import codex_watch_agent.settings as settings_module

    reloaded = importlib.reload(settings_module)

    assert reloaded.Settings().cache_ttl_seconds == 60


def test_quota_cache_max_age_defaults_to_install_friendly_window(monkeypatch) -> None:
    monkeypatch.setenv("PYTHON_DOTENV_DISABLED", "1")
    monkeypatch.delenv("QUOTA_CACHE_MAX_AGE_SECONDS", raising=False)

    import codex_watch_agent.settings as settings_module

    reloaded = importlib.reload(settings_module)

    assert reloaded.Settings().quota_cache_max_age_seconds == 1800


def test_quota_provider_timeout_defaults_below_phone_timeout(monkeypatch) -> None:
    monkeypatch.setenv("PYTHON_DOTENV_DISABLED", "1")
    monkeypatch.delenv("QUOTA_PROVIDER_TIMEOUT_SECONDS", raising=False)

    import codex_watch_agent.settings as settings_module

    reloaded = importlib.reload(settings_module)

    assert reloaded.Settings().quota_provider_timeout_seconds == 16


def test_settings_reads_environment_at_instantiation(monkeypatch) -> None:
    monkeypatch.setenv("PYTHON_DOTENV_DISABLED", "1")

    import codex_watch_agent.settings as settings_module

    reloaded = importlib.reload(settings_module)
    monkeypatch.setenv("AGENT_HOST", "0.0.0.0")
    monkeypatch.setenv("AGENT_PORT", "8799")
    monkeypatch.setenv("CODEX_BINARY", "/opt/homebrew/bin/codex")
    monkeypatch.setenv("CODEX_APP_SERVER_TIMEOUT_SECONDS", "31")
    monkeypatch.setenv("QUOTA_PROVIDER_TIMEOUT_SECONDS", "7")

    settings = reloaded.Settings()

    assert settings.host == "0.0.0.0"
    assert settings.port == 8799
    assert settings.codex_binary == "/opt/homebrew/bin/codex"
    assert settings.codex_app_server_timeout_seconds == 31
    assert settings.quota_provider_timeout_seconds == 7
