#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${CODEX_WATCH_ENV_FILE:-$ROOT/agent/.env}"
MAC_URL=""
HOST=""
PORT=""
HTML_OUT=""
OPEN_HTML=0

usage() {
  cat <<'EOF'
Usage: scripts/show-pairing-qr.sh [options]

Options:
  --url URL          Pair with an explicit Mac Agent URL, such as http://mac.local:8787.
  --host HOST        Override detected LAN host.
  --port PORT        Override AGENT_PORT from agent/.env.
  --html PATH        Write a browser-friendly HTML QR page to PATH.
  --open-html        Write a temporary HTML QR page and open it in the default browser.
  -h, --help         Show this help.

Prints a QR code for iPhone pairing. The QR contains Mac URL + WATCH_TOKEN, so
scan it only from your own iPhone and do not share screenshots of it. If the
terminal QR is hard to scan, use --open-html or --html /tmp/coding-quota-qr.html.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url)
      if [ "$#" -lt 2 ] || [[ "$2" == -* ]]; then
        echo "--url requires a value." >&2
        exit 2
      fi
      MAC_URL="$2"
      shift 2
      ;;
    --host)
      if [ "$#" -lt 2 ] || [[ "$2" == -* ]]; then
        echo "--host requires a value." >&2
        exit 2
      fi
      HOST="$2"
      shift 2
      ;;
    --port)
      if [ "$#" -lt 2 ] || [[ "$2" == -* ]]; then
        echo "--port requires a value." >&2
        exit 2
      fi
      PORT="$2"
      shift 2
      ;;
    --html)
      if [ "$#" -lt 2 ] || [[ "$2" == -* ]]; then
        echo "--html requires a value." >&2
        exit 2
      fi
      HTML_OUT="$2"
      shift 2
      ;;
    --open-html)
      OPEN_HTML=1
      shift
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
done

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE. Run scripts/bootstrap-local.sh --lan first." >&2
  exit 1
fi

env_value() {
  awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$ENV_FILE"
}

WATCH_TOKEN_VALUE="$(env_value WATCH_TOKEN)"
if [ "${#WATCH_TOKEN_VALUE}" -lt 24 ]; then
  echo "WATCH_TOKEN in $ENV_FILE is missing or too short; use at least 24 URL-safe characters." >&2
  exit 1
fi
if [[ ! "$WATCH_TOKEN_VALUE" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "WATCH_TOKEN in $ENV_FILE contains non URL-safe characters." >&2
  exit 1
fi

if [ -z "$PORT" ]; then
  PORT="$(env_value AGENT_PORT)"
fi
PORT="${PORT:-8787}"

detect_lan_host() {
  ipconfig getifaddr en0 2>/dev/null ||
    ipconfig getifaddr en1 2>/dev/null ||
    echo "127.0.0.1"
}

if [ -z "$MAC_URL" ]; then
  if [ -z "$HOST" ]; then
    HOST="$(detect_lan_host)"
  fi
  MAC_URL="http://${HOST}:${PORT}"
fi

case "$MAC_URL" in
  http://*|https://*)
    ;;
  *)
    echo "Mac Agent URL must start with http:// or https://." >&2
    exit 2
    ;;
esac

PYTHON_BIN="$ROOT/agent/.venv/bin/python"
if [ ! -x "$PYTHON_BIN" ]; then
  "$ROOT/scripts/bootstrap-local.sh" --skip-checks
fi

if ! "$PYTHON_BIN" -c "import qrcode" >/dev/null 2>&1; then
  "$PYTHON_BIN" -m pip --disable-pip-version-check install -q qrcode >/dev/null
fi

if [ "$OPEN_HTML" -eq 1 ] && [ -z "$HTML_OUT" ]; then
  HTML_OUT="${TMPDIR:-/tmp}/coding-quota-pair-qr.html"
fi

printf '%s\n%s\n%s\n' "$MAC_URL" "$WATCH_TOKEN_VALUE" "$HTML_OUT" | "$PYTHON_BIN" -c '
import html
from pathlib import Path
import sys
from urllib.parse import urlencode

import qrcode

mac_url = sys.stdin.readline().strip()
token = sys.stdin.readline().strip()
html_out = sys.stdin.readline().strip()
pairing_uri = "llmquota://pair?" + urlencode({"url": mac_url, "token": token})

qr = qrcode.QRCode(border=2)
qr.add_data(pairing_uri)
qr.make(fit=True)
if html_out:
    import qrcode.image.svg

    browser_qr = qrcode.QRCode(border=4, box_size=14)
    browser_qr.add_data(pairing_uri)
    browser_qr.make(fit=True)
    svg_img = browser_qr.make_image(image_factory=qrcode.image.svg.SvgPathImage)
    svg_path = Path(html_out).with_suffix(".svg")
    with svg_path.open("wb") as f:
        svg_img.save(f)
    svg = svg_path.read_text(encoding="utf-8")
    svg_path.unlink(missing_ok=True)
    page = f"""<!doctype html>
<html lang=\"zh-CN\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>Codex Quota Pairing QR</title>
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif; margin: 0; background: #f7f7f2; color: #161616; }}
  main {{ min-height: 100vh; display: grid; place-items: center; padding: 32px; box-sizing: border-box; }}
  section {{ max-width: 720px; width: 100%; text-align: center; }}
  .qr {{ background: white; padding: 24px; display: inline-block; border: 1px solid #ddd; }}
  .qr svg {{ width: min(82vw, 520px); height: auto; display: block; }}
  code {{ font-size: 16px; }}
  p {{ line-height: 1.5; }}
</style>
</head>
<body>
<main>
<section>
<h1>Codex Quota Pairing QR</h1>
<div class=\"qr\">{svg}</div>
<p>在 iPhone 的 <strong>Codex Quota</strong> 里点 <strong>Scan Pairing QR</strong> 扫这个码。</p>
<p>Mac URL: <code>{html.escape(mac_url)}</code></p>
<p>二维码包含 WATCH_TOKEN，只在本机使用，不要截图公开。</p>
</section>
</main>
</body>
</html>
"""
    out = Path(html_out)
    out.write_text(page, encoding="utf-8")
    out.chmod(0o600)
    print(f"Pairing QR HTML: {out}")
else:
    qr.print_ascii(invert=True)

print()
print("Scan this QR in the iPhone app: Codex Quota -> Scan Pairing QR")
print(f"Mac URL: {mac_url}")
print("WATCH_TOKEN: hidden in QR")
'

if [ "$OPEN_HTML" -eq 1 ]; then
  open "$HTML_OUT"
fi
