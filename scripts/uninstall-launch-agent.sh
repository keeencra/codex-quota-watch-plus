#!/usr/bin/env bash
set -euo pipefail

LABEL="${CODEX_WATCH_AGENT_LABEL:-com.codingquota.agent}"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
uid="$(id -u)"

usage() {
  cat <<'EOF'
Usage: scripts/uninstall-launch-agent.sh [options]

Options:
  -h, --help         Show this help.

Stops and removes the per-user macOS LaunchAgent. It leaves agent/.env and
local logs untouched.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
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
  shift
done

launchctl bootout "gui/${uid}/${LABEL}" >/dev/null 2>&1 || true
if [ -f "$PLIST" ]; then
  launchctl bootout "gui/${uid}" "$PLIST" >/dev/null 2>&1 || true
  rm -f "$PLIST"
  echo "Removed LaunchAgent: $PLIST"
else
  echo "LaunchAgent plist not found: $PLIST"
fi

echo "agent/.env and local logs were left untouched."
