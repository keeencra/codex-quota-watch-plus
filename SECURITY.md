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

Task snapshots include a project directory basename, hashed event ID, status and
timestamps. They exclude full paths, raw prompts, commands and response text.
Bark notifications contain only fixed status text. The private device key is never
returned in snapshots. Keep notifications.json, pairing pages and tunnel credentials private.

The pairing QR contains the current `WATCH_TOKEN`. If it may have been exposed,
rotate it and pair again:

```bash
scripts/rotate-watch-token.sh --restart-launch-agent
scripts/show-pairing-qr.sh
```

For remote personal access, prefer Tailscale Serve to route your private tailnet
to `127.0.0.1:8787`. Do not use Tailscale Funnel or expose the agent directly to
the public internet.

This version also offers an authenticated gateway on loopback port 8788 for an
HTTPS tunnel. Expose only that gateway, not the full agent on 8787. See
[remote setup](docs/enhancements.md).
