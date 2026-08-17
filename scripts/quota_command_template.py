#!/usr/bin/env python3
"""Template for CODEX_QUOTA_COMMAND or CLAUDE_QUOTA_COMMAND.

Print JSON in this shape. The Mac Agent will normalize it and send it to the watch.
"""
import json
from datetime import datetime, timedelta, timezone

now = datetime.now(timezone.utc)
print(json.dumps({
    "remaining_percent": 72,
    "used_percent": 28,
    "reset_at": (now + timedelta(hours=3, minutes=20)).isoformat(),
    "reset_in": "3h 20m",
    "window": "5h",
    "buckets": [
        {"label": "5h", "remaining_percent": 72, "reset_in": "3h 20m", "window": "5h"},
        {"label": "7d", "remaining_percent": 91, "reset_in": "4d 2h", "window": "7d"},
    ],
}))
