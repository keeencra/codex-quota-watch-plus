"""Local hook; optional permission requests wait for an explicit remote answer."""
import json
import os
import sys
from .task_events import TaskEventStore
from .approvals import ApprovalStore, await_decision


def main():
    os.umask(0o077)
    output = {}
    try:
        # Bound input size; never persist the raw hook payload.
        raw = sys.stdin.read(1024 * 1024 + 1)
        if len(raw) <= 1024 * 1024:
            event = json.loads(raw)
            if isinstance(event, dict):
                TaskEventStore().record(event)
                if event.get('hook_event_name') == 'PermissionRequest':
                    output = await_decision(event)
                elif event.get('hook_event_name') in ('Stop', 'Interrupt'):
                    ApprovalStore().cancel_turn(event)
    except Exception:
        print('Task notification was skipped.', file=sys.stderr)
    # Only a live, explicitly answered permission request may return a decision.
    print(json.dumps(output))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
