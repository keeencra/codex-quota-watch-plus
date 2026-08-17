# AGENTS.md Example

Copy this file to `AGENTS.md` for local Codex-assisted setup:

```bash
cp AGENTS.example.md AGENTS.md
```

`AGENTS.md` is ignored by git in this repository so local setup notes and device
state are not accidentally published.

## Project Goal

Set up the Codex Quota Apple Watch monitor for local personal use.

## Safe Commands

Use these commands first:

```bash
scripts/bootstrap-local.sh --lan
scripts/doctor.sh
STRICT_HISTORY=0 scripts/check-public-ready.sh --worktree
```

## Safety Rules

- Do not commit or upload `agent/.env`.
- Do not upload raw `~/.codex`, auth files, cookies, screenshots
  with account data, or Apple signing credentials.
- Do not run `git push --all`.
- Keep the Mac Agent local or trusted-LAN only.

## Expected Local Result

- `agent/.venv` exists.
- `agent/.env` exists with a generated `WATCH_TOKEN`.
- `scripts/doctor.sh` can find required local tools.
- `codex-watch-agent` can start on the Mac.
- The iPhone app can fetch `http://<Mac-LAN-IP>:8787/watch` with the same
  `WATCH_TOKEN`.
