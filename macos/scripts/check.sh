#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check_public.py
python3 scripts/test_parsing.py
python3 scripts/test_widgets.py
bash build_app.sh
codesign --verify --deep --strict "${OUTPUT_DIR:-$HOME/Library/Caches/CodeCompanionMac/build}/CodeCompanionMac.app"
python3 scripts/verify_widget_bundle.py "${OUTPUT_DIR:-$HOME/Library/Caches/CodeCompanionMac/build}/CodeCompanionMac.app"
