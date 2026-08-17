#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../agent"
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
pip install -e .
if [ ! -f .env ]; then
  token="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)"
  {
    echo "WATCH_TOKEN=${token}"
    echo "AGENT_HOST=127.0.0.1"
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
codex-watch-agent
