from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _copy_ios_files(tmp_path: Path) -> Path:
    workspace = tmp_path / "repo"
    workspace.mkdir()
    shutil.copytree(ROOT / "ios-watch", workspace / "ios-watch", ignore=shutil.ignore_patterns("build", ".build"))
    shutil.copytree(ROOT / "scripts", workspace / "scripts")
    return workspace


def test_configure_ios_identifiers_updates_all_project_ids(tmp_path: Path) -> None:
    workspace = _copy_ios_files(tmp_path)

    result = subprocess.run(
        [
            "bash",
            "scripts/configure-ios-identifiers.sh",
            "--bundle-id",
            "com.acme.CodingQuota",
            "--app-group",
            "group.com.acme.CodingQuota",
        ],
        cwd=workspace,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr

    files = {
        "project": workspace / "ios-watch/CodingQuota.xcodeproj/project.pbxproj",
        "shared": workspace / "ios-watch/Sources/Shared/UsageModels.swift",
        "phone_info": workspace / "ios-watch/Config/iPhoneApp-Info.plist",
        "watch_info": workspace / "ios-watch/Config/WatchApp-Info.plist",
        "phone_entitlements": workspace / "ios-watch/Config/iPhoneApp.entitlements",
        "watch_entitlements": workspace / "ios-watch/Config/WatchApp.entitlements",
        "widget_entitlements": workspace / "ios-watch/Config/WidgetExtension.entitlements",
    }
    text_by_name = {name: path.read_text() for name, path in files.items()}

    assert "PRODUCT_BUNDLE_IDENTIFIER = com.acme.CodingQuota;" in text_by_name["project"]
    assert "PRODUCT_BUNDLE_IDENTIFIER = com.acme.CodingQuota.watchkitapp;" in text_by_name["project"]
    assert "PRODUCT_BUNDLE_IDENTIFIER = com.acme.CodingQuota.widget;" in text_by_name["project"]
    assert "public static let appGroupID = \"group.com.acme.CodingQuota\"" in text_by_name["shared"]
    assert "public static let backgroundRefreshTaskID = \"com.acme.CodingQuota.refresh\"" in text_by_name["shared"]
    assert "<string>com.acme.CodingQuota.refresh</string>" in text_by_name["phone_info"]
    assert "<string>com.acme.CodingQuota</string>" in text_by_name["watch_info"]
    assert all("group.com.acme.CodingQuota" in text for name, text in text_by_name.items() if "entitlements" in name)
    assert "com.example.CodexQuota" not in "\n".join(text_by_name.values())
    assert "group.com.example.CodexQuota" not in "\n".join(text_by_name.values())


def test_configure_ios_identifiers_rejects_unsafe_values(tmp_path: Path) -> None:
    workspace = _copy_ios_files(tmp_path)

    result = subprocess.run(
        [
            "bash",
            "scripts/configure-ios-identifiers.sh",
            "--bundle-id",
            "com.acme bad",
        ],
        cwd=workspace,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode != 0
    assert "Invalid bundle id" in result.stderr
