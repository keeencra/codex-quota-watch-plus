# Mac Agent

## Install

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

Prefer the root bootstrap script for first setup because it generates a random
`WATCH_TOKEN`:

```bash
cd ..
scripts/bootstrap-local.sh --lan --skip-checks
```

## Codex quota

v0.2 defaults to:

```bash
codex app-server
# JSON-RPC method: account/rateLimits/read
```

Direct test:

```bash
codex-quota-app-server
codex-quota-app-server --raw
```

The normalized command writes the latest successful Codex result to a short-lived
local cache under `~/.cache/codex-quota-watch/codex.json`. If the Codex helper is
slow during an iPhone / Watch refresh, the agent can return that recent cache
instead of blocking the whole `/watch` response.

Expected normalized shape:

```json
{
  "remaining_percent": 72,
  "used_percent": 28,
  "reset_in": "3h 12m",
  "window": "5h",
  "buckets": [
    { "label": "codex 5h", "remaining_percent": 72, "reset_in": "3h 12m" }
  ]
}
```

## Run

```bash
codex-watch-agent
```

The default bind address is `127.0.0.1`. For iPhone/Watch testing on the same
Wi-Fi, set `AGENT_HOST=0.0.0.0` in `.env` and keep `WATCH_TOKEN` set to a long
random value. Tokens shorter than 24 URL-safe characters, non URL-safe tokens,
and placeholder tokens from `.env.example` are rejected at startup.

The public release contract does not expose local session titles, project paths, or
message previews. It only returns quota, bucket, today, and hourly token summary
data.

Endpoints:

```text
GET /health
GET /usage          internal full Pydantic JSON
GET /v1/snapshot    client snapshot grouped by provider
GET /watch          compact JSON for iPhone/Watch, including hourly heatmap data
```

The `/v1/snapshot` contract is documented in `../schemas/snapshot.schema.json`.
Sanitized examples live under `../docs/examples/`.

Set `WATCH_TOKEN` and pass it as header:

```bash
curl -H "x-watch-token: $WATCH_TOKEN" http://127.0.0.1:8787/watch
curl -H "x-watch-token: $WATCH_TOKEN" http://127.0.0.1:8787/v1/snapshot
```
