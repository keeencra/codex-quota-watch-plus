# Security Policy

This project is intended for local, personal monitoring. It reads local Codex
files and exposes only summarized data to your own iPhone and Apple Watch.

## Sensitive Data

Do not commit or share:

- `agent/.env`
- raw `~/.codex` files
- browser cookies, access tokens, auth files, API keys, or session files
- Xcode signing certificates, provisioning profiles, or private keys
- screenshots or logs that include account identifiers or tokens

The default `.gitignore` excludes local env files, virtual environments, Xcode
build output, and signing artifacts.

## Network Exposure

The Mac agent defaults to `127.0.0.1`. For iPhone and Apple Watch testing you can
bind to `0.0.0.0` on a trusted LAN, but you must set a `WATCH_TOKEN` with at
least 24 URL-safe random characters.

The agent refuses to start without `WATCH_TOKEN`, and common placeholder values
from examples, short values, and non URL-safe values are rejected.

The public release does not expose local session titles, project paths, or message
previews to the iPhone, Watch, or App Group snapshot storage.

The pairing QR contains the current `WATCH_TOKEN`. If it may have been exposed,
rotate it and pair again:

```bash
scripts/rotate-watch-token.sh --restart-launch-agent
scripts/show-pairing-qr.sh
```

For remote personal access, prefer Tailscale Serve to route your private tailnet
to `127.0.0.1:8787`. Do not use Tailscale Funnel or expose the agent directly to
the public internet.
