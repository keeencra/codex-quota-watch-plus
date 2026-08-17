from __future__ import annotations

import argparse
import json
import os
import selectors
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .quota_cache import write_quota_cache


class CodexRPCError(RuntimeError):
    pass


CODEX_CHILD_ENV_DENYLIST = {
    "AGENT_HOST",
    "AGENT_PORT",
    "CACHE_TTL_SECONDS",
    "CODEX_APP_SERVER_ENABLED",
    "CODEX_APP_SERVER_TIMEOUT_SECONDS",
    "CODEX_QUOTA_BEARER_TOKEN",
    "CODEX_QUOTA_CACHE_PATH",
    "CODEX_QUOTA_COMMAND",
    "CODEX_QUOTA_URL",
    "MAX_FILES_TO_SCAN",
    "OPENAI_ADMIN_KEY",
    "QUOTA_CACHE_MAX_AGE_SECONDS",
    "QUOTA_PROVIDER_TIMEOUT_SECONDS",
    "WATCH_TOKEN",
}


def _codex_child_env() -> dict[str, str]:
    env = {key: value for key, value in os.environ.items() if key not in CODEX_CHILD_ENV_DENYLIST}
    if "CODEX_HOME" in env:
        env["CODEX_HOME"] = str(Path(env["CODEX_HOME"]).expanduser())
    env.setdefault("NO_COLOR", "1")
    return env


@dataclass
class CodexRPCClient:
    codex_binary: str = "codex"
    timeout_seconds: int = 12

    def _send(self, proc: subprocess.Popen[str], payload: dict[str, Any]) -> None:
        if proc.stdin is None:
            raise CodexRPCError("codex app-server stdin is closed")
        proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        proc.stdin.flush()

    def _read_until_id(
        self,
        proc: subprocess.Popen[str],
        selector: selectors.BaseSelector,
        wanted_id: int,
        deadline: float,
    ) -> dict[str, Any]:
        while time.monotonic() < deadline:
            remaining = max(0.05, min(0.5, deadline - time.monotonic()))
            events = selector.select(timeout=remaining)
            if not events:
                continue
            for key, _ in events:
                line = key.fileobj.readline()
                if not line:
                    break
                try:
                    message = json.loads(line)
                except Exception:
                    continue

                # Server-initiated requests carry both id and method. We do not manage
                # external ChatGPT tokens; answer gracefully so the server can fail fast
                # instead of hanging the quota poller.
                if "method" in message and "id" in message and message.get("id") != wanted_id:
                    self._send(
                        proc,
                        {
                            "id": message["id"],
                            "error": {
                                "code": -32601,
                                "message": f"Client cannot handle server request {message.get('method')}",
                            },
                        },
                    )
                    continue

                if message.get("id") == wanted_id:
                    if "error" in message:
                        raise CodexRPCError(json.dumps(message["error"], ensure_ascii=False))
                    return message.get("result") or {}
        raise CodexRPCError(f"timed out waiting for JSON-RPC id={wanted_id}")

    def request(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        binary = shutil.which(self.codex_binary) or self.codex_binary
        # Do not pipe stderr without draining it: noisy Codex startup logs can fill
        # the pipe and block the JSON-RPC initialize response.
        env = _codex_child_env()
        proc = subprocess.Popen(
            [binary, "app-server"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            cwd=os.path.expanduser("~"),
            env=env,
            bufsize=1,
        )
        selector = selectors.DefaultSelector()
        try:
            if proc.stdout is None:
                raise CodexRPCError("codex app-server stdout is closed")
            selector.register(proc.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + self.timeout_seconds
            self._send(
                proc,
                {
                    "method": "initialize",
                    "id": 0,
                    "params": {
                        "clientInfo": {
                            "name": "coding_quota_watch",
                            "title": "Codex Quota Watch",
                            "version": "0.2.0",
                        }
                    },
                },
            )
            self._send(proc, {"method": "initialized", "params": {}})
            _ = self._read_until_id(proc, selector, 0, deadline)
            self._send(proc, {"method": method, "id": 1, "params": params or {}})
            return self._read_until_id(proc, selector, 1, deadline)
        finally:
            try:
                selector.close()
            except Exception:
                pass
            try:
                proc.terminate()
                proc.wait(timeout=1)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass


def read_codex_rate_limits(*, codex_binary: str = "codex", timeout_seconds: int = 12) -> dict[str, Any]:
    client = CodexRPCClient(codex_binary=codex_binary, timeout_seconds=timeout_seconds)
    return client.request("account/rateLimits/read")


def read_codex_account(*, codex_binary: str = "codex", timeout_seconds: int = 12) -> dict[str, Any]:
    client = CodexRPCClient(codex_binary=codex_binary, timeout_seconds=timeout_seconds)
    return client.request("account/read", {"refreshToken": False})


def _parse_dt(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc)
    if isinstance(value, (int, float)):
        ts = value / 1000 if value > 10_000_000_000 else value
        try:
            return datetime.fromtimestamp(ts, tz=timezone.utc)
        except Exception:
            return None
    if isinstance(value, str):
        s = value.strip()
        if not s:
            return None
        if s.isdigit():
            return _parse_dt(int(s))
        try:
            if s.endswith("Z"):
                s = s[:-1] + "+00:00"
            return datetime.fromisoformat(s).astimezone(timezone.utc)
        except Exception:
            return None
    return None


def _human_reset_in(reset_at: datetime | None) -> str | None:
    if reset_at is None:
        return None
    seconds = int((reset_at - datetime.now(timezone.utc)).total_seconds())
    if seconds <= 0:
        return "now"
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def _window_label(mins: Any) -> str | None:
    try:
        value = int(mins)
    except Exception:
        return None
    if value % (24 * 60) == 0:
        return f"{value // (24 * 60)}d"
    if value % 60 == 0:
        return f"{value // 60}h"
    return f"{value}m"


def _first_present(*values: Any) -> Any:
    for value in values:
        if value is not None:
            return value
    return None


def normalize_rate_limits_for_command(result: dict[str, Any]) -> dict[str, Any]:
    """Return the generic JSON shape accepted by CODEX_QUOTA_COMMAND.

    This is useful for shell debugging:
      codex-quota-app-server | jq
    """
    by_id = result.get("rateLimitsByLimitId")
    if not isinstance(by_id, dict):
        single = result.get("rateLimits")
        by_id = {single.get("limitId", "codex"): single} if isinstance(single, dict) else {}

    buckets: list[dict[str, Any]] = []
    for limit_id, raw_bucket in by_id.items():
        if not isinstance(raw_bucket, dict):
            continue
        for slot_name in ("primary", "secondary"):
            slot = raw_bucket.get(slot_name)
            if not isinstance(slot, dict):
                continue
            used_percent = _first_present(slot.get("usedPercent"), slot.get("used_percentage"))
            try:
                used = float(used_percent)
            except Exception:
                used = None
            reset_at = _parse_dt(slot.get("resetsAt") or slot.get("resetAt") or slot.get("reset_at"))
            window = _window_label(slot.get("windowDurationMins") or slot.get("window_duration_mins"))
            label_bits = [str(raw_bucket.get("limitName") or limit_id)]
            if window:
                label_bits.append(window)
            if slot_name == "secondary":
                label_bits.append("secondary")
            buckets.append(
                {
                    "id": f"{limit_id}:{slot_name}",
                    "label": " ".join(label_bits),
                    "used_percent": used,
                    "remaining_percent": None if used is None else max(0.0, min(100.0, 100.0 - used)),
                    "reset_at": reset_at.isoformat() if reset_at else None,
                    "reset_in": _human_reset_in(reset_at),
                    "window": window,
                    "status": "ok" if used is not None or reset_at else "partial",
                }
            )

    chosen = None
    ok_buckets = [b for b in buckets if isinstance(b.get("remaining_percent"), (int, float))]
    if ok_buckets:
        # For one-line display, show the most constrained active bucket.
        chosen = min(ok_buckets, key=lambda b: float(b["remaining_percent"]))
    elif buckets:
        chosen = buckets[0]

    return {
        "remaining_percent": chosen.get("remaining_percent") if chosen else None,
        "used_percent": chosen.get("used_percent") if chosen else None,
        "reset_at": chosen.get("reset_at") if chosen else None,
        "reset_in": chosen.get("reset_in") if chosen else None,
        "window": chosen.get("window") if chosen else None,
        "status": "ok" if ok_buckets else ("partial" if buckets else "error"),
        "buckets": buckets,
        "details": {
            "raw_keys": sorted(result.keys()),
            "rateLimitReachedType": (result.get("rateLimits") or {}).get("rateLimitReachedType") if isinstance(result.get("rateLimits"), dict) else None,
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read Codex ChatGPT quota via codex app-server JSON-RPC")
    parser.add_argument("--codex-binary", default=os.getenv("CODEX_BINARY", "codex"))
    parser.add_argument("--timeout", type=int, default=int(os.getenv("CODEX_APP_SERVER_TIMEOUT_SECONDS", "12")))
    parser.add_argument("--raw", action="store_true", help="print raw app-server result instead of normalized JSON")
    args = parser.parse_args(argv)
    try:
        result = read_codex_rate_limits(codex_binary=args.codex_binary, timeout_seconds=args.timeout)
        payload = result if args.raw else normalize_rate_limits_for_command(result)
        if not args.raw:
            write_quota_cache(provider="codex", payload=payload, source="codex-quota-app-server")
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0
    except Exception as exc:
        print(json.dumps({"status": "error", "error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
