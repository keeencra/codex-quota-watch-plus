import io
import json
import time
import httpx
import pytest
from codex_watch_agent.task_events import TaskEventStore, deliver_pending, save_bark_config, load_notification_config
from codex_watch_agent import task_hook


def event(kind, **extra):
    return dict(hook_event_name=kind, session_id='session', turn_id='turn', cwd='/private/project', **extra)


@pytest.fixture
def store(tmp_path):
    store = TaskEventStore(tmp_path)
    (tmp_path / 'notifications.json').write_text(json.dumps({'enabled': True, 'topic': 'codex-' + 'a'*32}))
    return store


def mock_client(calls, fail=False):
    def handle(request):
        calls.append(request)
        return httpx.Response(503 if fail else 200, json={'id': 'receipt'})
    return httpx.Client(transport=httpx.MockTransport(handle))


def test_local_history_never_persists_raw_prompt_or_path(store):
    assert store.record(event('UserPromptSubmit', prompt='SECRET-PROMPT', tool_input={'command':'SECRET-COMMAND'}))
    row = store.snapshot()['task_events'][0]
    assert row['project'] == 'project'
    assert row['status'] == 'running'
    assert 'SECRET' not in store.path.read_bytes().decode(errors='ignore')
    assert '/private' not in store.path.read_bytes().decode(errors='ignore')


def test_completion_deduplicates_and_publishes_status_only(store):
    store.record(event('UserPromptSubmit'))
    for _ in range(2):
        store.record(event('Stop', last_assistant_message='SECRET-REPLY'))
    calls = []
    with mock_client(calls) as client:
        assert deliver_pending(store, client=client) == 1
        assert deliver_pending(store, client=client) == 0
    assert len(calls) == 1
    request = calls[0]
    assert str(request.url) == 'https://ntfy.sh'
    body = request.content.decode()
    assert all(value not in body for value in ['SECRET', 'project', '/private', 'session', 'turn'])
    assert 'Cache' not in request.headers
    assert store.snapshot()['notifications']['last_delivery_at'] is not None


def test_distinct_approvals_notify_but_retries_do_not(store):
    for command in ['one', 'one', 'two']:
        store.record(event('PermissionRequest', tool_input={'command': command}))
    calls = []
    with mock_client(calls) as client:
        assert deliver_pending(store, client=client) == 2
    assert all(json.loads(r.content)['priority'] == 4 for r in calls)
    assert 'one' not in store.path.read_bytes().decode(errors='ignore')


def test_finished_turn_expires_pending_approval_and_ignores_late_start(store):
    store.record(event('PermissionRequest'))
    store.record(event('Stop'))
    assert not store.record(event('UserPromptSubmit'))
    calls = []
    with mock_client(calls) as client:
        assert deliver_pending(store, client=client) == 1
    assert '本轮已结束' in calls[0].content.decode()


def test_transient_error_retries_without_blocking_and_expires_after_deadline(store):
    store.record(event('Stop'))
    now = time.time()
    calls = []
    with mock_client(calls, fail=True) as client:
        assert deliver_pending(store, client=client, now=now) == 0
        assert deliver_pending(store, client=client, now=now+1) == 0
    assert len(calls) == 1
    with mock_client(calls) as client:
        assert deliver_pending(store, client=client, now=now+30) == 1
    store.record(dict(event('Stop'), turn_id='other'))
    with mock_client(calls) as client:
        assert deliver_pending(store, client=client, now=now+1000) == 0


def test_bad_config_cannot_redirect_pushes(store):
    (store.root / 'notifications.json').write_text(json.dumps({'enabled': True, 'topic': '../secret', 'server':'https://other.example'}))
    store.record(event('Stop'))
    calls = []
    with mock_client(calls) as client:
        assert deliver_pending(store, client=client) == 0
    assert not calls


def test_ignore_recursive_stop_subagents_and_invalid_events(store):
    for payload in [event('Stop', stop_hook_active=True), event('SubagentStop'), event('Stop',agent_id='child'), {}, {'hook_event_name':'Stop'}]:
        assert not store.record(payload)
    assert store.snapshot()['task_events'] == []


def test_hook_fail_open_and_no_permission_decision(monkeypatch, capsys):
    for payload in ['invalid json', json.dumps(event('PermissionRequest'))]:
        monkeypatch.setattr('sys.stdin', io.StringIO(payload))
        assert task_hook.main() == 0
        assert json.loads(capsys.readouterr().out) == {}


def test_interrupted_turn_cannot_later_report_completion(store):
    store.record(event('UserPromptSubmit'))
    store.record(event('Interrupt'))
    assert not store.record(event('Stop'))
    assert store.snapshot()['task_events'][0]['status'] == 'interrupted'
    assert store.snapshot()['notifications']['pending_count'] == 0


def test_bark_address_is_private_and_payload_goes_to_fixed_endpoint(store):
    key = 'privateBarkDevice123'
    save_bark_config('https://api.day.app/' + key + '/example', store.root)
    assert (store.root / 'notifications.json').stat().st_mode & 0o777 == 0o600
    assert load_notification_config(store.root)['device_key'] == key
    snapshot = store.snapshot()
    assert snapshot['notifications']['provider'] == 'bark'
    assert snapshot['notifications']['topic'] == ''
    assert key not in json.dumps(snapshot)
    store.record(event('Stop', last_assistant_message='PRIVATE TASK'))
    def handle(request):
        assert str(request.url) == 'https://api.day.app/push'
        payload = json.loads(request.content)
        assert payload['device_key'] == key
        assert payload['level'] == 'active'
        assert 'PRIVATE TASK' not in request.content.decode()
        return httpx.Response(200, json={'code': 200, 'message': 'success'})
    with httpx.Client(transport=httpx.MockTransport(handle)) as client:
        assert deliver_pending(store, client=client) == 1


@pytest.mark.parametrize('address', [None, '', 'https://api.day.app', 'https://evil.example/abcdefgh',
    'https://api.day.app@evil.example/abcdefgh', 'http://api.day.app/abcdefgh',
    'https://api.day.app:443/abcdefgh', 'https://api.day.app/abcdefgh?key=secret', '../abcdefgh'])
def test_invalid_bark_address_does_not_replace_working_config(store, address):
    previous = (store.root / 'notifications.json').read_bytes()
    with pytest.raises(ValueError):
        save_bark_config(address, store.root)
    assert (store.root / 'notifications.json').read_bytes() == previous


def test_bark_application_error_is_not_a_successful_delivery(store):
    save_bark_config('privateBarkDevice123', store.root)
    store.test_notification()
    with httpx.Client(transport=httpx.MockTransport(lambda request: httpx.Response(200, json={'code': 400, 'message': 'invalid key'}))) as client:
        assert deliver_pending(store, client=client) == 0
    snapshot = store.snapshot()['notifications']
    assert snapshot['last_delivery_at'] is None
    assert snapshot['pending_count'] == 1
