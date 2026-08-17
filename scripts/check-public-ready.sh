#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCAN_TARGET="${1:-HEAD}"
STRICT_HISTORY="${STRICT_HISTORY:-1}"
REQUIRE_XCODE_BUILDS="${REQUIRE_XCODE_BUILDS:-0}"

has_simulator_runtimes() {
  command -v xcrun >/dev/null 2>&1 || return 1
  xcrun simctl list runtimes --json 2>/dev/null | python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)

sys.exit(0 if any(runtime.get("isAvailable") for runtime in data.get("runtimes", [])) else 1)
  '
}

echo "== git whitespace check =="
git diff --check

if [ "$SCAN_TARGET" != "--worktree" ] && [ "$STRICT_HISTORY" = "1" ]; then
  echo "== publish branch history check =="
  commit_count="$(git rev-list --count "$SCAN_TARGET")"
  if [ "$commit_count" != "1" ]; then
    echo "Publish target must be a clean single-commit branch; found $commit_count commits in $SCAN_TARGET." >&2
    echo "Create or use a sanitized branch such as public-main, and do not push local working history." >&2
    exit 1
  fi
fi

echo "== tracked sensitive-pattern scan =="
SENSITIVE_PATTERN='(/Users/[[:alnum:]_.-]+|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|WATCH_TOKEN=[A-Za-z0-9_-]{12,}|sk-[A-Za-z0-9]{20,}|Bearer [A-Za-z0-9._-]{20,}|DEVELOPMENT_TEAM = [A-Z0-9]{10};|api[_-]?key[[:space:]]*=[[:space:]]*["'\'']?[A-Za-z0-9_-]{20,})'
if [ "$SCAN_TARGET" = "--worktree" ]; then
  tracked_matches="$(git grep -n -E "$SENSITIVE_PATTERN" -- . || true)"
  untracked_matches="$(git ls-files -z --others --exclude-standard | xargs -0 grep -nE "$SENSITIVE_PATTERN" -- 2>/dev/null || true)"
  matches="$(printf "%s\n%s\n" "$tracked_matches" "$untracked_matches")"
else
  matches="$(git grep -n -E "$SENSITIVE_PATTERN" "$SCAN_TARGET" -- . || true)"
fi
matches="$(printf "%s\n" "$matches" | grep -v -E 'WATCH_TOKEN=(replace-with-a-long-random-token|change-me-to-a-long-random-token|PASTE_GENERATED_TOKEN_HERE|<long-random-token>)' || true)"
if [ -n "$matches" ]; then
  printf "%s\n" "$matches"
  echo "Sensitive-looking tracked content found. Review before publishing." >&2
  exit 1
fi

echo "== shell script syntax checks =="
for script in scripts/*.sh; do
  bash -n "$script"
done

echo "== python tests =="
(
  cd agent
  if [ -d .venv ]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
  fi
  python3 -m pytest
)

if [ -f ios-watch/Package.swift ]; then
  echo "== swift shared tests =="
  swift test --package-path ios-watch
fi

if command -v xcodebuild >/dev/null 2>&1; then
  if has_simulator_runtimes || [ "$REQUIRE_XCODE_BUILDS" = "1" ]; then
    echo "== xcode unsigned app build =="
    xcodebuild -project ios-watch/CodingQuota.xcodeproj -target CodingQuota -configuration Debug CODE_SIGNING_ALLOWED=NO build
  else
    echo "== xcode unsigned app build skipped: no simulator runtimes installed =="
    echo "Install iOS/watchOS simulator runtimes, or run with REQUIRE_XCODE_BUILDS=1 to force the app build gate."
  fi
else
  echo "== xcode skipped: xcodebuild not found =="
fi

echo "== done =="
