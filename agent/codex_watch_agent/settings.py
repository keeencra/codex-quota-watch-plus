from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from pydantic import BaseModel, Field

load_dotenv()


def _bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "y", "on"}


def _int_env(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    return int(raw)


def _path_env(name: str, default: str) -> Path:
    return Path(os.getenv(name, default)).expanduser()


class Settings(BaseModel):
    host: str = Field(default_factory=lambda: os.getenv("AGENT_HOST", "127.0.0.1"))
    port: int = Field(default_factory=lambda: _int_env("AGENT_PORT", 8787))
    watch_token: str | None = Field(default_factory=lambda: os.getenv("WATCH_TOKEN"))

    codex_home: Path = Field(default_factory=lambda: _path_env("CODEX_HOME", "~/.codex"))

    # Generic quota endpoints/commands. These are intentionally configurable because
    # app subscription quota endpoints can change and may differ by plan/account type.
    codex_quota_command: str | None = Field(default_factory=lambda: os.getenv("CODEX_QUOTA_COMMAND"))

    codex_quota_url: str | None = Field(default_factory=lambda: os.getenv("CODEX_QUOTA_URL"))
    codex_quota_bearer_token: str | None = Field(default_factory=lambda: os.getenv("CODEX_QUOTA_BEARER_TOKEN"))

    # Codex app-server exact ChatGPT/Codex quota path.
    codex_app_server_enabled: bool = Field(default_factory=lambda: _bool_env("CODEX_APP_SERVER_ENABLED", True))
    codex_binary: str = Field(default_factory=lambda: os.getenv("CODEX_BINARY", "codex"))
    codex_app_server_timeout_seconds: int = Field(
        default_factory=lambda: _int_env("CODEX_APP_SERVER_TIMEOUT_SECONDS", 12)
    )
    quota_provider_timeout_seconds: int = Field(default_factory=lambda: _int_env("QUOTA_PROVIDER_TIMEOUT_SECONDS", 16))
    codex_quota_cache_path: str | None = Field(default_factory=lambda: os.getenv("CODEX_QUOTA_CACHE_PATH"))
    quota_cache_max_age_seconds: int = Field(default_factory=lambda: _int_env("QUOTA_CACHE_MAX_AGE_SECONDS", 1800))

    # Official Admin API for API usage, not personal ChatGPT/Codex subscription UI quota.
    openai_admin_key: str | None = Field(default_factory=lambda: os.getenv("OPENAI_ADMIN_KEY"))

    cache_ttl_seconds: int = Field(default_factory=lambda: _int_env("CACHE_TTL_SECONDS", 60))
    max_files_to_scan: int = Field(default_factory=lambda: _int_env("MAX_FILES_TO_SCAN", 400))
