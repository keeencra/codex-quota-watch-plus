import json
import importlib
import sqlite3

import pytest
from fastapi.testclient import TestClient

from codex_watch_agent.antigravity import AntigravityStore, install, normalize
from codex_watch_agent import public_gateway as gateway


def payload(**kwargs):
    return {'product': 'antigravity', 'conversation_id': 'private-session',
            'agent_state': 'working', 'model': {'display_name': 'Model A'},
            'quota': {'weekly': {'remaining_fraction': 0, 'reset_time': '2026-10-01T00:00:00Z'}},
            'email': 'private@example.com', 'cwd': '/private/project',
            'transcript_path': '/private/transcript', 'token': 'SECRET', **kwargs}


def test_allowlist_never_persists_credentials_or_paths(tmp_path):
    store = AntigravityStore(tmp_path)
    store.ingest(payload(), now=1000)
    raw = json.dumps(store.snapshot(now=1001))
    for private in ('private-session', 'private@example.com', '/private', 'SECRET', 'transcript'):
        assert private not in raw
        assert private.encode() not in store.path.read_bytes()
    assert store.path.stat().st_mode & 0o777 == 0o600
    row = store.snapshot(now=1001)['sessions'][0]
    assert row['quotas'][0]['remaining'] == 0  # exhausted is not missing
    assert row['quotas'][0]['reset'] == '2026-10-01T00:00:00+00:00'


@pytest.mark.parametrize('value', [None, True, '0.5', -0.1, 1.01, float('nan'), float('inf')])
def test_invalid_quota_is_not_fabricated(value):
    assert normalize(payload(quota={'a': {'remaining_fraction': value}}))['quotas'] == []


def test_idle_is_not_completion_and_unknown_not_running(tmp_path):
    store = AntigravityStore(tmp_path)
    store.ingest(payload(agent_state='idle', tool_confirmation_pending=True), now=1000)
    row = store.snapshot(now=1001)['sessions'][0]
    assert row['state'] == 'idle' and row['needs_confirmation']
    assert not (tmp_path / 'task-events.sqlite3').exists()
    assert normalize(payload(agent_state='finished'))['state'] == 'unknown'


def test_empty_stale_future_and_corrupt(tmp_path):
    store = AntigravityStore(tmp_path)
    assert store.snapshot()['status'] == 'not_connected'
    assert not store.path.exists()
    store.ingest(payload(), now=1000)
    assert store.snapshot(now=1899)['status'] == 'available'
    assert store.snapshot(now=1900)['status'] == 'stale'
    assert store.snapshot(now=0)['status'] == 'stale'
    with sqlite3.connect(store.path) as db:
        db.execute('UPDATE observations SET payload=?', ('{}',))
    assert store.snapshot()['status'] == 'unavailable'
    assert store.snapshot()['sessions'] == []


def test_sessions_are_isolated_and_bounded(tmp_path):
    store = AntigravityStore(tmp_path)
    for i in range(60):
        store.ingest(payload(conversation_id=str(i)), now=1000+i)
    snap = store.snapshot(now=1061)
    assert len(snap['sessions']) == 50
    assert snap['sessions'][0]['observed_at'] == 1059
    assert not any(snap['capabilities'][x] for x in ('reply', 'approval', 'balance', 'notifications'))


@pytest.mark.parametrize('value', [[], {}, {'product': 'codex'}, payload(conversation_id=None)])
def test_reject_unrelated_payloads(value):
    with pytest.raises(ValueError):
        normalize(value)


def test_installer_preserves_settings_and_existing_custom_command(tmp_path):
    path = tmp_path / 'settings.json'
    path.write_text('{"unrelated":true}')
    install(path)
    assert json.loads(path.read_text())['unrelated'] is True
    assert json.loads(path.with_name('settings.json.codecompanion-backup').read_text()) == {'unrelated': True}
    install(path)  # idempotent, original backup survives
    path.write_text('{"statusLine":{"command":"user-script"}}')
    with pytest.raises(ValueError):
        install(path)
    assert json.loads(path.read_text())['statusLine']['command'] == 'user-script'


def test_endpoint_auth_no_cache_and_no_actions(monkeypatch):
    importlib.reload(gateway)
    token = 'antigravity_test_watch_token_12345678'
    monkeypatch.setattr(gateway.settings, 'watch_token', token)
    client = TestClient(gateway.app)
    assert client.get('/antigravity').status_code == 401
    response = client.get('/antigravity', headers={'x-watch-token': token})
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'no-store'
    assert response.json()['status'] == 'not_connected'
    assert client.post('/antigravity', headers={'x-watch-token': token}, json={}).status_code == 405


def test_relative_state_directory(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    from pathlib import Path
    store = AntigravityStore(Path('relative-state'))
    store.ingest(payload(), now=1000)
    assert store.snapshot(now=1001)['status'] == 'available'


def test_malformed_optional_fields_do_not_discard_valid_quota():
    result = normalize(payload(agent_state=[], quota={
        'huge': {'remaining_fraction': 10**400},
        'valid': {'remaining_fraction': 0.5}
    }))
    assert result['state'] == 'unknown'
    assert len(result['quotas']) == 1


def test_concurrent_writers_and_authenticated_roundtrip(tmp_path, monkeypatch):
    from concurrent.futures import ThreadPoolExecutor
    store = AntigravityStore()
    with ThreadPoolExecutor(max_workers=8) as workers:
        list(workers.map(lambda i: store.ingest(payload(conversation_id=str(i)), now=1000+i), range(30)))
    assert len(store.snapshot(now=1030)['sessions']) == 30
    importlib.reload(gateway)
    token = 'antigravity_test_watch_token_12345678'
    monkeypatch.setattr(gateway.settings, 'watch_token', token)
    response = TestClient(gateway.app).get('/antigravity', headers={'x-watch-token': token})
    assert response.status_code == 200
    assert len(response.json()['sessions']) == 30
    assert response.json()['status'] == 'stale'
    assert response.json()['sessions'][0]['quotas'][0]['remaining'] == 0
    assert not (store.path.parent / 'task-events.sqlite3').exists()
