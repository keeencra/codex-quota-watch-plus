#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8787}"
TOKEN="${WATCH_TOKEN:-}"

echo "== health =="
curl -fsS "$BASE_URL/health"
echo

echo "== watch =="
if [[ -n "$TOKEN" ]]; then
  curl -fsS -H "x-watch-token: $TOKEN" "$BASE_URL/watch"
else
  curl -fsS "$BASE_URL/watch"
fi
echo
