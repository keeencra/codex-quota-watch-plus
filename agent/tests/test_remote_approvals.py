import io
import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient
from codex_watch_agent.approvals import ApprovalStore, ApprovalConflict, await_decision
from codex_watch_agent import public_gateway as gateway, task_hook
from codex_watch_agent.task_events import TaskEventStore


def event(**kwargs):
    return dict(hook_event_name='PermissionRequest', session_id='s', turn_id='t', tool_name='Bash',
                cwd='/private/example', tool_input={'command':'printf approval-test', 'description':'Smoke test'}, **kwargs)


@pytest.fixture
def store(tmp_path):
    root = tmp_path / 'approvals'
    root.mkdir()
    (root / 'remote-approval.json').write_text('{"enabled":true}')
    return ApprovalStore(root)


def decide(store, row, decision='allow', **kwargs):
    return store.decide(row['id'], row['nonce'], row['fingerprint'], decision, **kwargs)


def test_single_decision_consumed_exactly_once_and_clears_details(store):
    row = store.create(event(), now=100)
    assert row['details'].find('printf approval-test') >= 0
    assert decide(store, row, now=101) == 'submitted'
    assert store.tick(row['id'], now=102) == 'allow'
    assert store.tick(row['id'], now=103) == 'closed'
    assert store.get(row['id'], now=103)['details'] == ''
    assert decide(store, row, now=104) == 'consumed'
    with pytest.raises(ApprovalConflict):
        decide(store, row, 'deny', now=104)


def test_dead_hook_and_expiry_cannot_approve(store):
    row = store.create(event(), now=100)
    with pytest.raises(ApprovalConflict): decide(store, row, now=109)
    assert store.get(row['id'], now=109)['status'] == 'expired'
    row = store.create(event(), now=200, ttl=2)
    with pytest.raises(ApprovalConflict): decide(store, row, now=202)


def test_nonce_fingerprint_cross_request_and_scope_are_checked(store):
    a, b = store.create(event()), store.create(event())
    for nonce, fingerprint in [(b['nonce'],a['fingerprint']), (a['nonce'],'0'*64)]:
        with pytest.raises(ApprovalConflict): store.decide(a['id'], nonce, fingerprint, 'allow')
    with pytest.raises(ValueError): decide(store, a, 'allowForSession')
    assert store.get(a['id'])['status'] == 'pending'


def test_concurrent_conflicting_decisions_only_one_wins(store):
    row = store.create(event())
    def send(decision):
        try:return decide(store, row, decision)
        except ApprovalConflict:return 'conflict'
    with ThreadPoolExecutor(max_workers=2) as pool:
        result = list(pool.map(send, ['allow','deny']))
    assert sorted(result) == ['conflict', 'submitted']


def test_cancelled_turn_invalidates_even_submitted_decision(store):
    row = store.create(event())
    decide(store, row)
    store.cancel_turn(event())
    assert store.tick(row['id']) == 'closed'
    assert store.get(row['id'])['status'] == 'cancelled'


def test_complete_details_required_no_subagent_log_or_truncated_approval(store):
    for extra in ({'tool_input':{}}, {'tool_input':{'command':'x'*17000}}, {'agent_id':'child'}, {'hook_event_name':'Stop'}):
        value = event(); value.update(extra)
        with pytest.raises(ValueError):store.create(value)


def test_hook_waits_for_explicit_answer_and_returns_official_decision(store):
    result = []
    thread = threading.Thread(target=lambda: result.append(await_decision(event(),store)))
    thread.start()
    try:
        deadline = time.monotonic()+3
        while not store.pending() and time.monotonic()<deadline:time.sleep(.01)
        assert not result
        row = store.pending()[0]
        decide(store, row, 'deny')
        thread.join(3)
        assert result[0]['hookSpecificOutput']['decision']['behavior'] == 'deny'
        assert store.get(row['id'])['status'] == 'consumed'
    finally:
        store.cancel_turn(event()); thread.join(3)


def test_disable_while_waiting_falls_back_without_decision(store):
    result=[]
    thread=threading.Thread(target=lambda:result.append(await_decision(event(),store)))
    thread.start()
    deadline=time.monotonic()+3
    while not store.pending() and time.monotonic()<deadline:time.sleep(.01)
    (store.root/'remote-approval.json').write_text('{"enabled":false}')
    thread.join(3)
    assert result == [{}]
    assert store.pending() == []


def test_authenticated_api_to_waiting_hook_and_no_snapshot_leak(store, monkeypatch):
    monkeypatch.setenv('CODEX_QUOTA_STATE_DIR', str(store.root))
    monkeypatch.setattr(gateway.settings,'watch_token','test-approval-token-123456789')
    headers={'x-watch-token':'test-approval-token-123456789'}
    row=store.create(event())
    with TestClient(gateway.app) as client:
        assert client.get('/approvals').status_code==401
        assert client.post('/approvals/'+row['id']+'/decision',json={}).status_code==401
        response=client.get('/approvals',headers=headers)
        assert response.headers['cache-control']=='no-store'
        assert response.json()['requests'][0]['id']==row['id']
        body={k:row[k] for k in ('nonce','fingerprint')};body['decision']='allow'
        endpoint='/approvals/'+row['id']+'/decision'
        assert client.get(endpoint,headers=headers).status_code==405
        assert client.post(endpoint,headers={**headers,'origin':'https://evil.test'},json=body).status_code==403
        assert client.post(endpoint,headers=headers,content='x'*2049).status_code==413
        assert client.post(endpoint,headers=headers,json={**body,'command':'other'}).status_code==400
        assert client.post(endpoint,headers=headers,json=body).json()=={'status':'submitted'}
        assert store.tick(row['id'])=='allow'
        assert client.get('/approvals/'+row['id'],headers=headers).json()['status']=='consumed'
    assert 'printf approval-test' not in json.dumps(TaskEventStore(store.root).snapshot())
    assert 'printf approval-test' not in TaskEventStore(store.root).path.read_bytes().decode(errors='ignore')
