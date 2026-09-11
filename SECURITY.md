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
The separate authenticated `/tasks` endpoint can return local task titles and
allowlisted activity summaries. Native apps keep these in memory only, outside
quota snapshots, widgets and push payloads. Titles may be sensitive: keep the
paired token private. No task logs can grant approval.
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

## Remote approvals

Remote approval is opt-in and reuses the paired WATCH_TOKEN over HTTPS. This token can view complete pending operation details and submit one-shot decisions. Details stay out of quota snapshots, widgets, and third-party push payloads. Temporary details live in a separate owner-only approvals.sqlite3 and are cleared when consumed, cancelled, or expired.

Decisions require a live request, random nonce, immutable operation fingerprint, expiry check, and an explicit user action. No arbitrary command or session-wide policy can be submitted. The native adapter validates the local socket owner and protocol version and sends only accept/decline to the current request owner. Protocol mismatches and stale requests fail closed. See [remote approval limitations](docs/remote-approval.md).
