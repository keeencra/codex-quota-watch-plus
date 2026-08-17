from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _copy_scripts(tmp_path: Path) -> Path:
    workspace = tmp_path / "repo"
    workspace.mkdir()
    shutil.copytree(ROOT / "scripts", workspace / "scripts")
    (workspace / "agent").mkdir()
    return workspace


def test_rotate_watch_token_replaces_existing_token_without_printing_it(tmp_path: Path) -> None:
    workspace = _copy_scripts(tmp_path)
    env_path = workspace / "agent/.env"
    env_path.write_text(
        "\n".join(
            [
                "WATCH_" + "TOKEN=old_token_value_1234567890",
                "AGENT_HOST=127.0.0.1",
                "AGENT_PORT=8787",
            ]
        )
        + "\n"
    )

    result = subprocess.run(
        ["bash", "scripts/rotate-watch-token.sh"],
        cwd=workspace,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    updated = env_path.read_text()
    match = re.search(r"^WATCH_TOKEN=(.+)$", updated, re.MULTILINE)
    assert match is not None
    token = match.group(1)
    assert token != "old_token_value_1234567890"
    assert len(token) >= 24
    assert re.fullmatch(r"[A-Za-z0-9_-]+", token)
    assert "AGENT_HOST=127.0.0.1" in updated
    assert token not in result.stdout
    assert token not in result.stderr
    assert stat.S_IMODE(env_path.stat().st_mode) == 0o600


def test_rotate_watch_token_creates_env_when_missing(tmp_path: Path) -> None:
    workspace = _copy_scripts(tmp_path)

    result = subprocess.run(
        ["bash", "scripts/rotate-watch-token.sh"],
        cwd=workspace,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert (workspace / "agent/.env").exists()
    assert "WATCH_" + "TOKEN=" in (workspace / "agent/.env").read_text()
