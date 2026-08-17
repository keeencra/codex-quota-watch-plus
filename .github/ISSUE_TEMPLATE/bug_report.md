---
name: Bug report
about: Report a sanitized Mac Agent, iPhone, or Watch issue
title: ""
labels: bug
assignees: ""
---

## Area

- [ ] Mac Agent
- [ ] Codex quota
- [ ] iPhone app
- [ ] iPhone Widget
- [ ] Watch app
- [ ] Signing / install
- [ ] Documentation

## What happened

Describe the issue without including tokens, raw local session files, cookies,
auth files, account identifiers, Apple Team IDs, or private paths.

## Expected behavior

What should have happened?

## Sanitized diagnostics

Commands that are usually safe to share after replacing tokens and private paths
with placeholders:

```bash
curl http://127.0.0.1:8787/health
curl -H "x-watch-token: <redacted>" http://127.0.0.1:8787/watch
```

## Environment

- macOS:
- Xcode:
- iOS:
- watchOS:
- Python:
- Codex CLI:

## Checklist

- [ ] I removed tokens, account identifiers, cookies, auth files, and raw local logs.
- [ ] I checked `docs/troubleshooting.md`.
- [ ] I can reproduce the issue with the current repository version.
