from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _copy_doctor_workspace(tmp_path: Path) -> Path:
    workspace = tmp_path / "repo"
    workspace.mkdir()
    shutil.copytree(ROOT / "scripts", workspace / "scripts")
    (workspace / "agent").mkdir()
    subprocess.run(["git", "init"], cwd=workspace, check=True, capture_output=True)
    return workspace


def test_doctor_does_not_treat_endpoint_as_current_install_without_env(tmp_path: Path) -> None:
    workspace = _copy_doctor_workspace(tmp_path)

    result = subprocess.run(
        ["bash", "scripts/doctor.sh"],
        cwd=workspace,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "warn agent/.env does not exist" in result.stdout
    assert "ok   Mac Agent health endpoint responds" not in result.stdout
    assert "warn Mac Agent endpoint checks skipped until agent/.env exists" in result.stdout
