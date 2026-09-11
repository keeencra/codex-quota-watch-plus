import json
import sqlite3
from fastapi.testclient import TestClient
from codex_watch_agent.task_events import TaskEventStore
from codex_watch_agent.task_dashboard import task_dashboard
from codex_watch_agent import public_gateway as gateway


def record(store, session='s', turn='t', kind='Activity', at=100, **extra):
    store.record(dict(session_id=session, turn_id=turn, cwd='/private/project', hook_event_name=kind, **extra), occurred_at=at)


def test_latest_turn_per_task_counts_beyond_ten_and_marks_old_activity(tmp_path):
    store = TaskEventStore(tmp_path / 'state')
    for i in range(15):
        record(store, session=str(i))
    record(store, session='0', turn='next', kind='Stop', at=101)
    data = task_dashboard(store, codex_home=tmp_path, now=110)
    assert len(data['tasks']) == 15
    assert sum(t['status'] == 'running' for t in data['tasks']) == 14
    assert len(store.snapshot()['task_events']) == 10
    old = task_dashboard(store, codex_home=tmp_path, now=2000)
    assert sum(t['stale'] for t in old['tasks']) == 14


def test_allowlisted_phases_and_private_title_never_enter_quota_or_push(tmp_path):
    store = TaskEventStore(tmp_path / 'state')
    with sqlite3.connect(tmp_path / 'state_5.sqlite') as db:
        db.execute('CREATE TABLE threads (id TEXT, title TEXT)')
        db.execute('INSERT INTO threads VALUES (?,?)', ('s', 'Private task title'))
    record(store, activity='tool', tool_input={'command': 'SECRET'})
    record(store, at=101, activity='tool')
    record(store, at=102, activity='tool_result')
    record(store, at=103, activity='injected SECRET')
    row = task_dashboard(store, codex_home=tmp_path, now=110)['tasks'][0]
    assert row['title'] == 'Private task title'
    assert len(row['recent']) == 3
    assert row['recent'][1]['text'] == '已收到工具结果'
    assert 'SECRET' not in json.dumps(row)
    assert 'Private task title' not in json.dumps(store.snapshot())
    assert 'SECRET' not in store.path.read_bytes().decode(errors='ignore')


def test_late_activity_does_not_replace_terminal_phase(tmp_path):
    store = TaskEventStore(tmp_path)
    record(store, kind='Stop', at=102)
    record(store, at=103, activity='tool')
    row = task_dashboard(store, codex_home=tmp_path, now=110)['tasks'][0]
    assert row['status'] == 'finished'
    assert row['phase'] == '本轮处理已结束'
    assert len(row['recent']) == 1


def test_configured_tilde_home_resolves_task_titles(tmp_path, monkeypatch):
    monkeypatch.setenv('HOME',str(tmp_path))
    monkeypatch.setenv('CODEX_HOME','~/.codex')
    home=tmp_path/'.codex';home.mkdir()
    with sqlite3.connect(home/'state_5.sqlite') as db:
        db.execute('CREATE TABLE threads (id TEXT, title TEXT)')
        db.execute('INSERT INTO threads VALUES (?,?)',('s','Task title'))
    store=TaskEventStore(tmp_path/'state');record(store)
    assert task_dashboard(store,now=110)['tasks'][0]['title']=='Task title'


def test_task_endpoint_requires_token_and_does_not_cache(tmp_path, monkeypatch):
    monkeypatch.setenv('CODEX_QUOTA_STATE_DIR', str(tmp_path))
    monkeypatch.setattr(gateway.settings, 'watch_token', 'dashboard-test-token-123456789')
    record(TaskEventStore(tmp_path))
    with TestClient(gateway.app) as client:
        assert client.get('/tasks').status_code == 401
        response = client.get('/tasks', headers={'x-watch-token': 'dashboard-test-token-123456789'})
        assert response.status_code == 200
        assert response.headers['cache-control'] == 'no-store'
        assert len(response.json()['tasks']) == 1
