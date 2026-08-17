# Contributing

This is a local-first Apple Watch utility that reads sensitive developer data.
Keep changes small, privacy-preserving, and easy to verify.

## Setup

Use the normal local setup path:

```bash
scripts/bootstrap-local.sh --lan
```

Detailed device setup lives in `docs/setup.md`.

## Checks

Run the checks that match your change:

```bash
cd agent && python3 -m pytest
swift test --package-path ios-watch
scripts/check-public-ready.sh --worktree
```

For iOS/watchOS UI changes, also run an unsigned Xcode build locally when Xcode
is available.

## Privacy Rules

- Do not commit `agent/.env`, `WATCH_TOKEN`, raw `~/.codex`,
  cookies, auth files, signing files, Apple Team IDs, or private keys.
- Do not publish logs or screenshots that show account identifiers or tokens.
- Do not expose the Mac Agent to the public internet.

## Contribution License

By submitting a pull request, you agree that your contribution may be licensed
under this project's AGPL-3.0 license.
