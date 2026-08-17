#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/agent/.env"
LABEL="${CODEX_WATCH_AGENT_LABEL:-com.codingquota.agent}"
RESTART_LAUNCH_AGENT=0

usage() {
  cat <<'EOF'
Usage: scripts/rotate-watch-token.sh [--restart-launch-agent]

Generates a new WATCH_TOKEN in agent/.env without printing it.
After rotation, pair the iPhone again with scripts/show-pairing-qr.sh.

Options:
  --restart-launch-agent  Restart the per-user LaunchAgent after updating .env.
  -h, --help              Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --restart-launch-agent)
      RESTART_LAUNCH_AGENT=1
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
  shift
done

mkdir -p "$ROOT/agent"
new_token="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)"

umask 077
if [ -f "$ENV_FILE" ]; then
  TOKEN="$new_token" ENV_FILE="$ENV_FILE" python3 <<'PY'
from __future__ import annotations

import os
from pathlib import Path

env_file = Path(os.environ["ENV_FILE"])
token = os.environ["TOKEN"]
lines = env_file.read_text().splitlines()
out: list[str] = []
replaced = False
for line in lines:
    if line.startswith("WATCH_TOKEN="):
        if not replaced:
            out.append(f"WATCH_TOKEN={token}")
            replaced = True
        continue
    out.append(line)
if not replaced:
    out.insert(0, f"WATCH_TOKEN={token}")
env_file.write_text("\n".join(out).rstrip() + "\n")
PY
else
  TOKEN="$new_token" ENV_FILE="$ENV_FILE" python3 <<'PY'
from __future__ import annotations

import os
from pathlib import Path

Path(os.environ["ENV_FILE"]).write_text(f"WATCH_TOKEN={os.environ['TOKEN']}\n")
PY
fi
chmod 600 "$ENV_FILE"

echo "WATCH_TOKEN rotated in agent/.env."

if [ "$RESTART_LAUNCH_AGENT" = "1" ]; then
  uid="$(id -u)"
  if launchctl print "gui/${uid}/${LABEL}" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/${uid}/${LABEL}"
    echo "Restarted LaunchAgent: ${LABEL}"
  else
    echo "LaunchAgent is not loaded; start it with scripts/install-launch-agent.sh"
  fi
else
  echo "Restart the Mac Agent, then run scripts/show-pairing-qr.sh and scan again."
fi
