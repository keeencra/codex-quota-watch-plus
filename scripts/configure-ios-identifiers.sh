#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID=""
APP_GROUP=""

usage() {
  cat <<'EOF'
Usage: scripts/configure-ios-identifiers.sh --bundle-id <id> [--app-group <group-id>]

Examples:
  scripts/configure-ios-identifiers.sh --bundle-id com.yourname.CodexQuota
  scripts/configure-ios-identifiers.sh --bundle-id com.yourname.CodexQuota --app-group group.com.yourname.CodexQuota

Updates local Xcode identifiers only:
  - iPhone app bundle id
  - watchOS app bundle id
  - iPhone widget extension bundle id
  - App Group entitlement ids
  - Swift AppConstants app group and background refresh task id

It does not configure Apple Team signing. Choose your Team in Xcode after this.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --app-group)
      APP_GROUP="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$BUNDLE_ID" ]; then
  echo "Missing --bundle-id." >&2
  usage >&2
  exit 2
fi

if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$ ]]; then
  echo "Invalid bundle id: $BUNDLE_ID" >&2
  exit 2
fi

if [ -z "$APP_GROUP" ]; then
  APP_GROUP="group.${BUNDLE_ID}"
fi

if [[ ! "$APP_GROUP" =~ ^group\.[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$ ]]; then
  echo "Invalid app group id: $APP_GROUP" >&2
  exit 2
fi

PHONE_ID="$BUNDLE_ID"
WATCH_ID="${BUNDLE_ID}.watchkitapp"
WIDGET_ID="${BUNDLE_ID}.widget"
BACKGROUND_TASK_ID="${BUNDLE_ID}.refresh"

PHONE_ID="$PHONE_ID" \
WATCH_ID="$WATCH_ID" \
WIDGET_ID="$WIDGET_ID" \
APP_GROUP="$APP_GROUP" \
BACKGROUND_TASK_ID="$BACKGROUND_TASK_ID" \
ROOT="$ROOT" \
python3 <<'PY'
from __future__ import annotations

import os
import re
from pathlib import Path

root = Path(os.environ["ROOT"])
phone_id = os.environ["PHONE_ID"]
watch_id = os.environ["WATCH_ID"]
widget_id = os.environ["WIDGET_ID"]
app_group = os.environ["APP_GROUP"]
background_task_id = os.environ["BACKGROUND_TASK_ID"]


def replace_text(path: Path, replacements: list[tuple[str, str]]) -> None:
    text = path.read_text()
    updated = text
    for pattern, replacement in replacements:
        updated = re.sub(pattern, replacement, updated)
    if updated != text:
        path.write_text(updated)


project_path = root / "ios-watch/CodingQuota.xcodeproj/project.pbxproj"
project_text = project_path.read_text()


def replace_bundle_id(match: re.Match[str]) -> str:
    current = match.group("value")
    if current.endswith(".watchkitapp"):
        value = watch_id
    elif current.endswith(".widget"):
        value = widget_id
    else:
        value = phone_id
    return f"{match.group('prefix')}{value};"


project_text = re.sub(
    r"(?P<prefix>PRODUCT_BUNDLE_IDENTIFIER = )(?P<value>[A-Za-z0-9.-]+);",
    replace_bundle_id,
    project_text,
)
project_path.write_text(project_text)

replace_text(
    root / "ios-watch/Sources/Shared/UsageModels.swift",
    [
        (r'public static let appGroupID = "[^"]+"', f'public static let appGroupID = "{app_group}"'),
        (
            r'public static let backgroundRefreshTaskID = "[^"]+"',
            f'public static let backgroundRefreshTaskID = "{background_task_id}"',
        ),
    ],
)

replace_text(
    root / "ios-watch/Config/iPhoneApp-Info.plist",
    [(r"<string>[A-Za-z0-9.-]+\.refresh</string>", f"<string>{background_task_id}</string>")],
)

replace_text(
    root / "ios-watch/Config/WatchApp-Info.plist",
    [(r"<key>WKCompanionAppBundleIdentifier</key>\s*<string>[^<]+</string>", f"<key>WKCompanionAppBundleIdentifier</key>\n\t<string>{phone_id}</string>")],
)

for entitlements in (
    root / "ios-watch/Config/iPhoneApp.entitlements",
    root / "ios-watch/Config/WatchApp.entitlements",
    root / "ios-watch/Config/WidgetExtension.entitlements",
):
    replace_text(entitlements, [(r"<string>group\.[^<]+</string>", f"<string>{app_group}</string>")])

print("Updated iOS/watchOS identifiers:")
print(f"  iPhone bundle id: {phone_id}")
print(f"  Watch bundle id:  {watch_id}")
print(f"  Widget bundle id: {widget_id}")
print(f"  App Group:        {app_group}")
print(f"  BG task id:       {background_task_id}")
PY

echo
echo "Next: open ios-watch/CodingQuota.xcodeproj and choose your Apple Team for each target."
