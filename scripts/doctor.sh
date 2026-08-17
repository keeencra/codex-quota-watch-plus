#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

status=0
LABEL="${CODEX_WATCH_AGENT_LABEL:-com.codingquota.agent}"
WATCH_TOKEN_PLACEHOLDERS=(
  "change-me-to-a-long-random-token"
  "replace-with-a-long-random-token"
  "PASTE_GENERATED_TOKEN_HERE"
  "<long-random-token>"
)

check_command() {
  local name="$1"
  local required="$2"
  if command -v "$name" >/dev/null 2>&1; then
    echo "ok   command: $name"
  elif [ "$required" = "required" ]; then
    echo "fail command: $name is required" >&2
    status=1
  else
    echo "warn command: $name is optional"
  fi
}

env_value() {
  local key="$1"
  if [ ! -f agent/.env ]; then
    return 0
  fi
  awk -F= -v key="$key" '
    $1 == key {
      value = substr($0, index($0, "=") + 1)
    }
    END {
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      gsub(/^"|"$/, "", value)
      gsub(/^'\''|'\''$/, "", value)
      print value
    }
  ' agent/.env
}

is_placeholder_token() {
  local token="$1"
  local placeholder
  for placeholder in "${WATCH_TOKEN_PLACEHOLDERS[@]}"; do
    if [ "$token" = "$placeholder" ]; then
      return 0
    fi
  done
  return 1
}

is_url_safe_token() {
  local token="$1"
  [[ "$token" =~ ^[A-Za-z0-9_-]+$ ]]
}

check_file_absent_from_git() {
  local path="$1"
  if git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    echo "fail tracked local file: $path" >&2
    status=1
  else
    echo "ok   not tracked: $path"
  fi
}

echo "== tools =="
check_command python3 required
check_command git required
check_command swift optional
check_command xcodebuild optional
check_command codex optional
check_command curl required
check_command jq optional
check_command gh optional

if [ "$status" -ne 0 ]; then
  echo
  echo "Fix required commands before continuing." >&2
  exit "$status"
fi

echo
echo "== local files and secrets =="
check_file_absent_from_git "agent/.env"
check_file_absent_from_git "agent/.venv"
check_file_absent_from_git "ios-watch/build"
check_file_absent_from_git "ios-watch/.build"

if [ -f agent/.env ]; then
  echo "ok   agent/.env exists"
  env_perm="$(stat -f "%Lp" agent/.env 2>/dev/null || stat -c "%a" agent/.env 2>/dev/null || true)"
  if [ "$env_perm" = "600" ]; then
    echo "ok   agent/.env permissions are 600"
  else
    echo "fail agent/.env permissions are ${env_perm:-unknown}; run: chmod 600 agent/.env" >&2
    status=1
  fi
else
  echo "warn agent/.env does not exist; run scripts/bootstrap-local.sh"
fi

watch_token="$(env_value WATCH_TOKEN)"
if [ -f agent/.env ]; then
  if [ -z "$watch_token" ]; then
    echo "fail WATCH_TOKEN is missing from agent/.env" >&2
    status=1
  elif is_placeholder_token "$watch_token"; then
    echo "fail WATCH_TOKEN is still an example placeholder" >&2
    status=1
  elif [ "${#watch_token}" -lt 24 ]; then
    echo "fail WATCH_TOKEN is too short; use at least 24 URL-safe random characters" >&2
    status=1
  elif ! is_url_safe_token "$watch_token"; then
    echo "fail WATCH_TOKEN contains non URL-safe characters" >&2
    status=1
  else
    echo "ok   WATCH_TOKEN is configured and passes local strength checks"
  fi
fi

echo
echo "== agent endpoint and launchd =="
host="127.0.0.1"
port="8787"
if [ -f agent/.env ]; then
  env_host="$(env_value AGENT_HOST)"
  env_port="$(env_value AGENT_PORT)"
  if [ -n "$env_host" ] && [ "$env_host" != "0.0.0.0" ]; then
    host="$env_host"
  fi
  if [ -n "$env_port" ]; then
    port="$env_port"
  fi
fi

case "${env_host:-127.0.0.1}" in
  127.0.0.1|localhost|"")
    echo "ok   AGENT_HOST is loopback-only"
    ;;
  0.0.0.0)
    echo "warn AGENT_HOST=0.0.0.0 exposes the agent on trusted LAN; keep WATCH_TOKEN private"
    ;;
  *)
    echo "warn AGENT_HOST=${env_host} is custom; confirm it is not public"
    ;;
esac

uid="$(id -u)"
plist="$HOME/Library/LaunchAgents/${LABEL}.plist"
if [ -f "$plist" ]; then
  echo "ok   LaunchAgent plist exists: $plist"
else
  echo "warn LaunchAgent plist not found; install with scripts/install-launch-agent.sh"
fi
if command -v launchctl >/dev/null 2>&1 && launchctl print "gui/${uid}/${LABEL}" >/dev/null 2>&1; then
  echo "ok   LaunchAgent is loaded: ${LABEL}"
else
  echo "warn LaunchAgent is not loaded: ${LABEL}"
fi

health_json="$(mktemp -t codex-watch-health.XXXXXX)"
watch_json="$(mktemp -t codex-watch-watch.XXXXXX)"
trap 'rm -f "$health_json" "$watch_json"' EXIT
if [ ! -f agent/.env ]; then
  echo "warn Mac Agent endpoint checks skipped until agent/.env exists; run scripts/bootstrap-local.sh"
else
  if curl -fsS "http://${host}:${port}/health" >"$health_json" 2>/dev/null; then
    echo "ok   Mac Agent health endpoint responds at http://${host}:${port}/health"
    python3 - "$HOME" "$health_json" <<'PY'
import pathlib
import sys

home = sys.argv[1]
health_path = pathlib.Path(sys.argv[2])
text = health_path.read_text()
if home:
    text = text.replace(home, "~")
print(text)
PY
  else
    echo "warn Mac Agent is not responding at http://${host}:${port}/health"
    echo "     Start it with: cd agent && source .venv/bin/activate && codex-watch-agent"
  fi

  if [ -n "${watch_token:-}" ] && [ "${#watch_token}" -ge 24 ] && is_url_safe_token "$watch_token"; then
    if WATCH_TOKEN="$watch_token" python3 - "http://${host}:${port}/watch" "$watch_json" <<'PY'
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

url = sys.argv[1]
out_path = pathlib.Path(sys.argv[2])
request = urllib.request.Request(url, headers={"x-watch-token": os.environ["WATCH_TOKEN"]})
try:
    with urllib.request.urlopen(request, timeout=20) as response:
        out_path.write_bytes(response.read())
except Exception as exc:
    print(f"warn Mac Agent /watch did not return a valid snapshot: {exc}")
    raise SystemExit(1)
PY
  then
    echo "ok   Mac Agent /watch accepts the configured WATCH_TOKEN"
    python3 - "$watch_json" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(f"     updated_at: {data.get('updated_at', '--')}")
for provider in ("codex",):
    item = data.get(provider) or {}
    status = item.get("status", "--")
    source = item.get("source", "--")
    print(f"     {provider}: status={status} source={source}")
PY
    fi
  fi
fi

echo
echo "== git =="
current_branch="$(git branch --show-current 2>/dev/null || true)"
echo "branch: ${current_branch:-unknown}"
if git status --short | grep -q .; then
  echo "warn working tree has changes"
  git status --short
else
  echo "ok   tracked working tree is clean"
fi

exit "$status"
