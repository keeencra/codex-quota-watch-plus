from pathlib import Path

from codex_watch_agent.codex_rpc import normalize_rate_limits_for_command
from codex_watch_agent.codex_rpc import read_codex_rate_limits
from codex_watch_agent.quota import _normalize_codex_app_server


def _rate_limit_payload() -> dict:
    return {
        "rateLimits": {
            "limitId": "codex",
            "primary": {
                "usedPercent": 19,
                "windowDurationMins": 300,
                "resetsAt": 1781218851,
            },
        },
        "rateLimitsByLimitId": {
            "codex_zero": {
                "limitId": "codex_zero",
                "limitName": "Codex Zero",
                "primary": {
                    "usedPercent": 0,
                    "windowDurationMins": 300,
                    "resetsAt": 1781229930,
                },
            },
            "codex": {
                "limitId": "codex",
                "limitName": None,
                "primary": {
                    "usedPercent": 19,
                    "windowDurationMins": 300,
                    "resetsAt": 1781218851,
                },
            },
        },
    }


def test_command_normalization_preserves_zero_used_percent() -> None:
    normalized = normalize_rate_limits_for_command(_rate_limit_payload())

    zero_bucket = next(
        bucket for bucket in normalized["buckets"] if bucket["id"] == "codex_zero:primary"
    )

    assert zero_bucket["used_percent"] == 0.0
    assert zero_bucket["remaining_percent"] == 100.0


def test_app_server_normalization_preserves_zero_used_percent() -> None:
    normalized = _normalize_codex_app_server(_rate_limit_payload())

    zero_bucket = next(
        bucket for bucket in normalized.buckets if bucket.id == "codex_zero:primary"
    )

    assert zero_bucket.used_percent == 0.0
    assert zero_bucket.remaining_percent == 100.0


def test_app_server_normalization_chooses_zero_remaining_as_most_constrained() -> None:
    payload = _rate_limit_payload()
    payload["rateLimitsByLimitId"]["codex_zero"]["primary"]["usedPercent"] = 100

    normalized = _normalize_codex_app_server(payload)

    assert normalized.used_percent == 100.0
    assert normalized.remaining_percent == 0.0


def test_codex_rpc_does_not_block_on_stderr_noise(tmp_path) -> None:
    fake_codex = tmp_path / "codex"
    fake_codex.write_text(
        "#!/usr/bin/env python3\n"
        "import json, sys\n"
        "if sys.argv[1:] != ['app-server']:\n"
        "    raise SystemExit(2)\n"
        "sys.stderr.write('x' * 200000)\n"
        "sys.stderr.flush()\n"
        "for line in sys.stdin:\n"
        "    msg = json.loads(line)\n"
        "    if msg.get('method') == 'initialize':\n"
        "        print(json.dumps({'id': msg['id'], 'result': {}}), flush=True)\n"
        "    elif msg.get('method') == 'account/rateLimits/read':\n"
        "        print(json.dumps({'id': msg['id'], 'result': {'rateLimits': {}}}), flush=True)\n"
        "        break\n"
    )
    fake_codex.chmod(0o755)

    payload = read_codex_rate_limits(codex_binary=str(fake_codex), timeout_seconds=5)

    assert payload == {"rateLimits": {}}


def test_codex_rpc_strips_agent_environment_and_expands_codex_home_for_child_process(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("WATCH_TOKEN", "test-watch-token")
    monkeypatch.setenv("CODEX_QUOTA_COMMAND", "codex-quota-app-server")
    monkeypatch.setenv("CODEX_APP_SERVER_ENABLED", "true")
    monkeypatch.setenv("CODEX_HOME", "~/.codex")
    monkeypatch.setenv("AGENT_PORT", "8788")
    fake_codex = tmp_path / "codex"
    fake_codex.write_text(
        "#!/usr/bin/env python3\n"
        "import json, os, sys\n"
        "if sys.argv[1:] != ['app-server']:\n"
        "    raise SystemExit(2)\n"
        "for line in sys.stdin:\n"
        "    msg = json.loads(line)\n"
        "    if msg.get('method') == 'initialize':\n"
        "        print(json.dumps({'id': msg['id'], 'result': {}}), flush=True)\n"
        "    elif msg.get('method') == 'account/rateLimits/read':\n"
        "        print(json.dumps({'id': msg['id'], 'result': {\n"
        "            'hasWatchToken': 'WATCH_TOKEN' in os.environ,\n"
        "            'hasQuotaCommand': 'CODEX_QUOTA_COMMAND' in os.environ,\n"
        "            'hasAppServerEnabled': 'CODEX_APP_SERVER_ENABLED' in os.environ,\n"
        "            'codexHome': os.environ.get('CODEX_HOME'),\n"
        "            'hasAgentPort': 'AGENT_PORT' in os.environ,\n"
        "        }}), flush=True)\n"
        "        break\n"
    )
    fake_codex.chmod(0o755)

    payload = read_codex_rate_limits(codex_binary=str(fake_codex), timeout_seconds=5)

    assert payload == {
        "hasWatchToken": False,
        "hasQuotaCommand": False,
        "hasAppServerEnabled": False,
        "codexHome": str(Path("~/.codex").expanduser()),
        "hasAgentPort": False,
    }
