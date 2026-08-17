#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="${CODEX_WATCH_AGENT_LABEL:-com.codingquota.agent}"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs"
LAN_MODE=0
RUN_CHECKS=0

usage() {
  cat <<'EOF'
Usage: scripts/install-launch-agent.sh [options]

Options:
  --lan              Configure first-time agent/.env to listen on 0.0.0.0 for LAN testing.
  --run-checks       Run the repository readiness checks during bootstrap.
  -h, --help         Show this help.

Installs a per-user macOS LaunchAgent so the Mac Agent starts at login and
restarts if it crashes. The script never prints WATCH_TOKEN.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --lan)
      LAN_MODE=1
      ;;
    --run-checks)
      RUN_CHECKS=1
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

bootstrap_args=()
if [ "$LAN_MODE" = "1" ]; then
  bootstrap_args+=(--lan)
fi
if [ "$RUN_CHECKS" = "0" ]; then
  bootstrap_args+=(--skip-checks)
fi

"$ROOT/scripts/bootstrap-local.sh" "${bootstrap_args[@]}"

mkdir -p "$PLIST_DIR" "$LOG_DIR"

tmp_plist="$(mktemp)"
cleanup() {
  if [ -n "${tmp_plist:-}" ]; then
    rm -f "$tmp_plist"
  fi
}
trap cleanup EXIT

cat > "$tmp_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${ROOT}/scripts/run-agent.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/${LABEL}.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/${LABEL}.err.log</string>
</dict>
</plist>
EOF

plutil -lint "$tmp_plist" >/dev/null

uid="$(id -u)"
launchctl bootout "gui/${uid}/${LABEL}" >/dev/null 2>&1 || true
if [ -f "$PLIST" ]; then
  launchctl bootout "gui/${uid}" "$PLIST" >/dev/null 2>&1 || true
fi

port="$(awk -F= '/^AGENT_PORT=/{print $2}' "$ROOT/agent/.env" 2>/dev/null | tail -n 1)"
port="${port:-8787}"
if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $port is already in use. Stop the foreground Mac Agent first, then rerun this script." >&2
  echo "Current listener:" >&2
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2 || true
  listener_pids="$(lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | paste -sd, -)"
  if [ -n "$listener_pids" ]; then
    echo "Listener command:" >&2
    ps -p "$listener_pids" -o pid,ppid,command >&2 || true
  fi
  rm -f "$tmp_plist"
  exit 1
fi

mv "$tmp_plist" "$PLIST"
tmp_plist=""
chmod 644 "$PLIST"

launchctl bootstrap "gui/${uid}" "$PLIST"
launchctl enable "gui/${uid}/${LABEL}"
launchctl kickstart -k "gui/${uid}/${LABEL}"

echo "Installed LaunchAgent: $PLIST"
echo "Status:"
echo "  launchctl print gui/${uid}/${LABEL}"
echo "Logs:"
echo "  tail -f \"$LOG_DIR/${LABEL}.out.log\""
echo "  tail -f \"$LOG_DIR/${LABEL}.err.log\""
echo "Health:"
echo "  curl http://127.0.0.1:${port}/health"
