"""Fast, local-only hook. A separate worker performs all network delivery."""
import json
import os
import sys
from .task_events import TaskEventStore


def main():
    os.umask(0o077)
    try:
        # Bound input size; never persist the raw hook payload.
        raw = sys.stdin.read(1024 * 1024 + 1)
        if len(raw) <= 1024 * 1024:
            event = json.loads(raw)
            if isinstance(event, dict):
                TaskEventStore().record(event)
    except Exception:
        print('Task notification was skipped.', file=sys.stderr)
    # No approval decision, continuation request, or blocking status.
    print('{}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
