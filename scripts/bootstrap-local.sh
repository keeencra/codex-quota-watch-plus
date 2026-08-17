#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_DIR="$ROOT/agent"
LAN_MODE=0
RUN_CHECKS=1

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-local.sh [options]

Options:
  --lan              Configure the Mac Agent to listen on 0.0.0.0 for iPhone/Watch LAN testing.
  --skip-checks      Skip pytest/swift/xcode readiness checks.
  -h, --help         Show this help.

This script creates agent/.env only when it does not already exist.
It never prints or uploads raw ~/.codex, auth files, cookies, or tokens.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --lan)
      LAN_MODE=1
      ;;
    --skip-checks)
      RUN_CHECKS=0
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

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_command python3
if [ "$RUN_CHECKS" = "1" ]; then
  need_command git
fi

echo "== prepare Python agent environment =="
cd "$AGENT_DIR"
if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e '.[test]'

echo "== prepare agent/.env =="
if [ -f .env ]; then
  echo "agent/.env already exists; leaving it unchanged."
else
  token="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)"
  host="127.0.0.1"
  if [ "$LAN_MODE" = "1" ]; then
    host="0.0.0.0"
  fi
  {
    echo "WATCH_TOKEN=${token}"
    echo "AGENT_HOST=${host}"
    echo "AGENT_PORT=8787"
    echo "CACHE_TTL_SECONDS=60"
    echo "CODEX_HOME=~/.codex"
    echo "CODEX_APP_SERVER_ENABLED=true"
    echo "CODEX_BINARY=codex"
    echo "CODEX_APP_SERVER_TIMEOUT_SECONDS=12"
    echo "MAX_FILES_TO_SCAN=400"
  } > .env
  chmod 600 .env
  echo "Created agent/.env with a generated WATCH_TOKEN."
fi

cd "$ROOT"
if [ "$RUN_CHECKS" = "1" ]; then
  echo "== run local readiness checks =="
  STRICT_HISTORY=0 scripts/check-public-ready.sh --worktree
fi

agent_port="$(awk -F= '/^AGENT_PORT=/{print $2}' "$AGENT_DIR/.env" 2>/dev/null | tail -n 1)"
agent_port="${agent_port:-8787}"

echo "== next steps =="
echo "Start the Mac Agent:"
echo "  cd \"$AGENT_DIR\""
echo "  source .venv/bin/activate"
echo "  codex-watch-agent"
echo
echo "In another terminal, test:"
echo "  curl http://127.0.0.1:${agent_port}/health"
echo "  curl -H \"x-watch-token: <WATCH_TOKEN from agent/.env>\" http://127.0.0.1:${agent_port}/watch"
if [ "$LAN_MODE" = "1" ]; then
  mac_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
  if [ -n "$mac_ip" ]; then
    echo
    echo "Use this iPhone Mac Agent URL on the same Wi-Fi:"
    echo "  http://${mac_ip}:${agent_port}"
  fi
fi
