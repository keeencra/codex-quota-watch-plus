#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUTPUT_DIR:-$HOME/Library/Caches/CodeCompanionMac/build}"
APP="$OUT/CodeCompanionMac.app"
NEXT_APP="$(/usr/bin/mktemp -d /tmp/codex-usage-build.XXXXXX)/CodeCompanionMac.app"
NEXT_BIN="$NEXT_APP/Contents/MacOS/CodexUsageBar"
trap 'rm -rf "$(dirname "$NEXT_APP")"' EXIT

clean_xattrs() {
  local path="$1"
  xattr -cr "$path" 2>/dev/null || true
  xattr -dr com.apple.FinderInfo "$path" 2>/dev/null || true
  xattr -dr 'com.apple.fileprovider.fpfs#P' "$path" 2>/dev/null || true
  xattr -dr com.apple.ResourceFork "$path" 2>/dev/null || true
  xattr -dr com.apple.provenance "$path" 2>/dev/null || true
}

mkdir -p "$NEXT_APP/Contents/MacOS" "$NEXT_APP/Contents/Resources"

swiftc -D WIDGET_SUPPORT \
  -O \
  -framework AppKit \
  "$ROOT/main.swift" "$ROOT/Sources/Shared/WidgetSnapshot.swift" \
  -o "$NEXT_BIN"

cat > "$NEXT_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexUsageBar</string>
  <key>CFBundleIdentifier</key>
  <string>local.codex.usagebar</string>
  <key>CFBundleName</key>
  <string>CodeCompanionMac</string>
  <key>CFBundleDisplayName</key>
  <string>码伴 Mac</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>3.1.0</string>
  <key>CFBundleVersion</key>
  <string>28</string>
  <key>CFBundleURLTypes</key>
  <array><dict><key>CFBundleURLName</key><string>local.codex.usagebar</string><key>CFBundleURLSchemes</key><array><string>codexusagebar</string></array></dict></array>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

WIDGET="$NEXT_APP/Contents/PlugIns/CodexUsageWidget.appex"
mkdir -p "$WIDGET/Contents/MacOS"
cp "$ROOT/Sources/Widget/Info.plist" "$WIDGET/Contents/Info.plist"
swiftc -O -parse-as-library -application-extension -Xlinker -e -Xlinker _NSExtensionMain -target "$(uname -m)-apple-macos14.0" \
  -framework SwiftUI -framework WidgetKit \
  "$ROOT/Sources/Shared/WidgetSnapshot.swift" "$ROOT/Sources/Widget/QuotaWidget.swift" "$ROOT/Sources/Widget/ClassicWidget.swift" "$ROOT/../shared-widgets/ClassicQuotaView.swift" "$ROOT/../shared-widgets/WidgetAppearance.swift" "$ROOT/../ios-watch/Sources/Shared/UsageModels.swift" \
  -o "$WIDGET/Contents/MacOS/CodexUsageWidget"
python3 "$ROOT/scripts/build_icon.py" "$NEXT_APP/Contents/Resources/AppIcon.icns"
chmod +x "$NEXT_BIN"
clean_xattrs "$NEXT_APP"
python3 "$ROOT/scripts/sign_app.py" "$NEXT_APP"
ditto "$NEXT_APP" "$APP"
clean_xattrs "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
