## Scope

Describe the user-visible change and the smallest area of the project it touches.

## Safety Checklist

- [ ] No raw `~/.codex`, auth files, cookies, Apple signing files, or real tokens are included.
- [ ] `agent/.env`, build products, Xcode user data, and local handoff files are not tracked.
- [ ] New screenshots, logs, fixtures, and examples are sanitized.

## Verification

Run the relevant checks and paste the command results:

```bash
STRICT_HISTORY=0 scripts/check-public-ready.sh --worktree
```

If you skipped a check, explain why and what risk remains.

## Device Notes

For iPhone/Watch changes, include:

- iPhone model / iOS version:
- Watch model / watchOS version:
- Xcode version:
- Signing mode:
- What was tested on device:
