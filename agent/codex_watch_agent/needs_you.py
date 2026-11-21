"""Build a local, read-only summary of work that needs the user.

The mobile clients can derive this from their authenticated task and approval
requests. This module also writes a mode-600 snapshot for the native Mac menu
bar app, so the Mac never needs access to the remote-control token.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import tempfile
import time

from .task_events import TaskEventStore, state_dir


STATE_NEEDS_YOU = "needs_you"
STATE_ATTENTION = "attention"
STATE_RUNNING = "running"
STATE_IDLE = "idle"


def _clean(value, limit):
    text = " ".join(str(value or "").split())
    return "".join(char for char in text if char.isprintable())[:limit]


def _task_item(task):
    return {
        "id": _clean(task.get("id"), 160),
        "kind": "task",
        "title": _clean(task.get("title") or task.get("project") or "未命名任务", 160),
        "project": _clean(task.get("project"), 80),
        "status": _clean(task.get("status"), 40),
        "summary": _clean(task.get("phase"), 160),
        "updated_at": _clean(task.get("updated_at"), 64),
    }


def _approval_item(approval):
    project = _clean(approval.get("project"), 80) or "Codex"
    tool = _clean(approval.get("tool"), 80) or "操作"
    return {
        "id": _clean(approval.get("id"), 160),
        "kind": "approval",
        "title": f"{project} · {tool}",
        "project": project,
        "status": "needs_approval",
        "summary": "等待你查看完整操作并确认",
        "updated_at": datetime.fromtimestamp(
            float(approval.get("created") or 0), timezone.utc
        ).isoformat(),
    }


def build_needs_you_snapshot(tasks, approvals=(), *, now=None):
    """Return a deterministic, privacy-bounded summary for all clients."""
    now = time.time() if now is None else now
    tasks = list(tasks or [])
    approvals = list(approvals or [])

    approval_items = sorted(
        (_approval_item(row) for row in approvals),
        key=lambda item: item["updated_at"],
        reverse=True,
    )
    input_tasks = [
        task for task in tasks
        if task.get("status") == "needs_input" and not task.get("stale")
    ]
    attention_tasks = [
        task for task in tasks
        if task.get("stale")
        or task.get("status") in ("stalled", "interrupted")
        or (task.get("status") == "needs_approval" and not approvals)
    ]
    running_tasks = [
        task for task in tasks
        if task.get("status") == "running" and not task.get("stale")
    ]

    input_items = [_task_item(task) for task in input_tasks]
    attention_items = [_task_item(task) for task in attention_tasks]
    running_items = [_task_item(task) for task in running_tasks]
    items = approval_items + input_items + attention_items + running_items

    needs_you_count = len(approval_items) + len(input_items)
    attention_count = len(attention_items)
    running_count = len(running_items)
    if needs_you_count:
        state, count = STATE_NEEDS_YOU, needs_you_count
    elif attention_count:
        state, count = STATE_ATTENTION, attention_count
    elif running_count:
        state, count = STATE_RUNNING, running_count
    else:
        state, count = STATE_IDLE, 0

    return {
        "state": state,
        "count": count,
        "approval_count": len(approval_items),
        "input_count": len(input_items),
        "attention_count": attention_count,
        "running_count": running_count,
        "updated_at": datetime.fromtimestamp(now, timezone.utc).isoformat(),
        "items": items[:20],
    }


def write_needs_you_snapshot(snapshot, *, root=None):
    root = Path(root or state_dir()).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    root.chmod(0o700)
    path = root / "needs-you-snapshot.json"
    fd, temporary = tempfile.mkstemp(prefix=".needs-you-", dir=root)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(snapshot, handle, ensure_ascii=False, separators=(",", ":"))
            handle.write("\n")
        os.replace(temporary, path)
        path.chmod(0o600)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return path


def refresh_needs_you_snapshot(*, store=None, root=None, now=None):
    """Re-read local task and approval state and atomically update its snapshot."""
    from .approvals import ApprovalStore
    from .task_dashboard import task_dashboard

    store = store or TaskEventStore(root)
    tasks = task_dashboard(store, now=now).get("tasks", [])
    approvals = ApprovalStore(store.root).pending(now=now)
    snapshot = build_needs_you_snapshot(tasks, approvals, now=now)
    write_needs_you_snapshot(snapshot, root=store.root)
    return snapshot
