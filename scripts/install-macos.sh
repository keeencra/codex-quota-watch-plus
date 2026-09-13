#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/macos/build_app.sh"
python3 "$ROOT/macos/scripts/install.py" "${OUTPUT_DIR:-$HOME/Library/Caches/CodeCompanionMac/build}/CodeCompanionMac.app"
