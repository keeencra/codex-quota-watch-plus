from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _copy_scripts_workspace(tmp_path: Path) -> Path:
    workspace = tmp_path / "repo"
    workspace.mkdir()
    shutil.copytree(ROOT / "scripts", workspace / "scripts")
    (workspace / "agent").mkdir()
    return workspace


def _write_noop_command(path: Path, body: str = "exit 0\n") -> None:
    path.write_text("#!/usr/bin/env bash\n" + body)
    path.chmod(0o755)


def test_install_launch_agent_reports_configured_port(tmp_path: Path) -> None:
    workspace = _copy_scripts_workspace(tmp_path)
    (workspace / "agent/.env").write_text("WATCH_" + "TOKEN=valid_watch_token_1234567890\nAGENT_PORT=8799\n")
    _write_noop_command(workspace / "scripts/bootstrap-local.sh")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _write_noop_command(bin_dir / "plutil")
    _write_noop_command(bin_dir / "launchctl")
    _write_noop_command(bin_dir / "lsof", "exit 1\n")

    env = os.environ.copy()
    env["HOME"] = str(tmp_path / "home")
    env["PATH"] = f"{bin_dir}{os.pathsep}{env['PATH']}"

    result = subprocess.run(
        ["bash", "scripts/install-launch-agent.sh"],
        cwd=workspace,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "curl http://127.0.0.1:8799/health" in result.stdout
    assert "curl http://127.0.0.1:8787/health" not in result.stdout


def test_bootstrap_reports_configured_port(tmp_path: Path) -> None:
    workspace = _copy_scripts_workspace(tmp_path)
    (workspace / "agent/.env").write_text("WATCH_" + "TOKEN=valid_watch_token_1234567890\nAGENT_PORT=8799\n")
    venv_bin = workspace / "agent/.venv/bin"
    venv_bin.mkdir(parents=True)
    (venv_bin / "activate").write_text("")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _write_noop_command(bin_dir / "python")
    _write_noop_command(bin_dir / "pip")

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}{os.pathsep}{env['PATH']}"

    result = subprocess.run(
        ["bash", "scripts/bootstrap-local.sh", "--skip-checks"],
        cwd=workspace,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "curl http://127.0.0.1:8799/health" in result.stdout
    assert "curl -H \"x-watch-token: <WATCH_TOKEN from agent/.env>\" http://127.0.0.1:8799/watch" in result.stdout
    assert "curl http://127.0.0.1:8787/health" not in result.stdout


def test_run_agent_adds_homebrew_paths_for_launchd() -> None:
    script = (ROOT / "scripts/run-agent.sh").read_text()

    assert "/opt/homebrew/bin" in script
    assert "/usr/local/bin" in script
    assert "export PATH=" in script


def test_public_ready_scan_checks_modified_tracked_files(tmp_path: Path) -> None:
    workspace = _copy_scripts_workspace(tmp_path)
    project_file = workspace / "project.pbxproj"
    project_file.write_text("DEVELOPMENT_TEAM = \"\";\n")
    subprocess.run(["git", "init"], cwd=workspace, check=True, capture_output=True)
    subprocess.run(["git", "add", "project.pbxproj"], cwd=workspace, check=True, capture_output=True)
    project_file.write_text("DEVELOPMENT_TEAM = " + "U8W93S96W9;\n")

    result = subprocess.run(
        ["bash", "scripts/check-public-ready.sh", "--worktree"],
        cwd=workspace,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 1
    assert "Sensitive-looking tracked content found" in result.stderr
    assert "project.pbxproj:1" in result.stdout
