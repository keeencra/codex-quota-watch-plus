import json
import stat

from codex_watch_agent.needs_you import (
    STATE_ATTENTION,
    STATE_IDLE,
    STATE_NEEDS_YOU,
    STATE_RUNNING,
    build_needs_you_snapshot,
    write_needs_you_snapshot,
)


def task(identifier, status, *, stale=False, title=None):
    return {
        "id": identifier,
        "project": "Project",
        "title": title or identifier,
        "status": status,
        "phase": "正在执行工具",
        "updated_at": "2026-11-21T08:00:00+00:00",
        "stale": stale,
    }


def approval(identifier="approval-1"):
    return {
        "id": identifier,
        "project": "Project",
        "tool": "Bash",
        "created": 1_764_000_000,
    }


def test_needs_you_approval_and_input_have_priority_over_running_and_attention():
    snapshot = build_needs_you_snapshot(
        [
            task("input", "needs_input"),
            task("stalled", "stalled"),
            task("running", "running"),
        ],
        [approval()],
        now=1_764_000_100,
    )
    assert snapshot["state"] == STATE_NEEDS_YOU
    assert snapshot["count"] == 2
    assert snapshot["approval_count"] == 1
    assert snapshot["input_count"] == 1
    assert snapshot["attention_count"] == 1
    assert snapshot["running_count"] == 1
    assert [item["kind"] for item in snapshot["items"]] == [
        "approval",
        "task",
        "task",
        "task",
    ]


def test_attention_precedes_running_and_stale_running_is_not_reported_as_running():
    snapshot = build_needs_you_snapshot(
        [task("old", "running", stale=True), task("running", "running")],
        now=1_764_000_100,
    )
    assert snapshot["state"] == STATE_ATTENTION
    assert snapshot["count"] == 1
    assert snapshot["attention_count"] == 1
    assert snapshot["running_count"] == 1


def test_running_and_idle_states_and_finished_tasks_stay_out_of_inbox():
    snapshot = build_needs_you_snapshot(
        [task("running", "running"), task("done", "finished")],
        now=1_764_000_100,
    )
    assert snapshot["state"] == STATE_RUNNING
    assert snapshot["count"] == 1
    assert [item["id"] for item in snapshot["items"]] == ["running"]

    idle = build_needs_you_snapshot(
        [task("done", "finished"), task("unknown", "untracked")],
        now=1_764_000_100,
    )
    assert idle["state"] == STATE_IDLE
    assert idle["count"] == 0
    assert idle["items"] == []


def test_snapshot_is_private_and_atomic_json(tmp_path):
    snapshot = build_needs_you_snapshot([task("running", "running")], now=1_764_000_100)
    path = write_needs_you_snapshot(snapshot, root=tmp_path)
    assert json.loads(path.read_text()) == snapshot
    assert stat.S_IMODE(tmp_path.stat().st_mode) == 0o700
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
