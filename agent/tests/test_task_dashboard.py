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
    monkeypatch.setenv('CODEX_HOME', str(tmp_path))
    monkeypatch.setattr(gateway.settings, 'watch_token', 'dashboard-test-token-123456789')
    record(TaskEventStore(tmp_path))
    with TestClient(gateway.app) as client:
        assert client.get('/tasks').status_code == 401
        response = client.get('/tasks', headers={'x-watch-token': 'dashboard-test-token-123456789'})
        assert response.status_code == 200
        assert response.headers['cache-control'] == 'no-store'
        assert len(response.json()['tasks']) == 1


def catalog_db(home):
    db = sqlite3.connect(home / 'state_5.sqlite')
    db.execute('CREATE TABLE threads (id TEXT, title TEXT, name TEXT, project_id TEXT, cwd TEXT, archived INTEGER, created_at INTEGER, updated_at INTEGER)')
    db.execute('CREATE TABLE projects (id TEXT, name TEXT, position INTEGER)')
    db.execute('CREATE TABLE project_roots (project_id TEXT, position INTEGER, path TEXT)')
    return db


def test_desktop_renames_legacy_assignments_and_archived_tasks(tmp_path):
    with catalog_db(tmp_path) as db:
        db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?)', ('s', 'Original prompt', 'Renamed task', None, '/work/elsewhere', 0, 50, 100))
        db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?)', ('old', 'Archived', None, None, '/work/p', 1, 50, 100))
        db.execute('INSERT INTO projects VALUES (?,?,?)', ('native', 'Native project', 0))
    state = {'local-projects': {'legacy': {'name': 'Sidebar project', 'rootPaths': ['/work/p']}},
             'app-server-project-id-by-legacy-project-id-by-host': {'local:' + str(tmp_path): {'legacy': 'native'}},
             'thread-project-assignments': {'s': {'projectKind': 'local', 'projectId': 'legacy'}}}
    (tmp_path / '.codex-global-state.json').write_text(json.dumps(state))
    store = TaskEventStore(tmp_path / 'events')
    record(store); record(store, session='old')
    tasks = task_dashboard(store, codex_home=tmp_path, now=110)['tasks']
    assert len(tasks) == 1
    assert (tasks[0]['id'], tasks[0]['title'], tasks[0]['project'], tasks[0]['project_id']) == ('s', 'Renamed task', 'Sidebar project', 'native')
    assert '/work' not in json.dumps(tasks)
    assert 'Renamed task' not in json.dumps(store.snapshot())
    with sqlite3.connect(tmp_path / 'state_5.sqlite') as db:
        db.execute('UPDATE threads SET name=? WHERE id=?', ('New title', 's'))
    assert task_dashboard(store, codex_home=tmp_path, now=110)['tasks'][0]['title'] == 'New title'


def test_unobserved_tasks_are_not_running_and_project_ids_do_not_merge(tmp_path):
    with catalog_db(tmp_path) as db:
        for i in range(2):
            db.execute('INSERT INTO projects VALUES (?,?,?)', (str(i), 'Same name', i))
            db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?)', ('s'+str(i), 'Title '+str(i), None, str(i), '/work/p', 0, 50, 100))
    store = TaskEventStore(tmp_path / 'events')
    tasks = task_dashboard(store, codex_home=tmp_path, now=110)['tasks']
    assert len(tasks) == 2
    assert all(t['status'] == 'untracked' and not t['stale'] for t in tasks)
    assert {t['project_id'] for t in tasks} == {'0', '1'}
    assert not store.snapshot()['task_events']


def test_project_root_fallback_uses_longest_boundary_and_honors_projectless(tmp_path):
    with catalog_db(tmp_path) as db:
        for pid, path in [('outer', '/work/p'), ('inner', '/work/p/nested')]:
            db.execute('INSERT INTO projects VALUES (?,?,?)', (pid, pid, 0))
            db.execute('INSERT INTO project_roots VALUES (?,?,?)', (pid, 0, path))
        for sid, cwd in [('nested', '/work/p/nested/src'), ('prefix', '/work/project'), ('free', '/work/p'), ('assigned', '/other')]:
            db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?)', (sid, 'Title', None, 'outer' if sid=='assigned' else None, cwd, 0, 50, 100))
    (tmp_path / '.codex-global-state.json').write_text(json.dumps({'projectless-thread-ids':['free'], 'thread-project-assignments':{'assigned':{'projectKind':'local','projectId':'inner'}}}))
    tasks = {t['id']: t for t in task_dashboard(TaskEventStore(tmp_path/'events'), codex_home=tmp_path, now=110)['tasks']}
    assert tasks['nested']['project_id'] == 'inner'
    assert tasks['prefix']['project_id'] == 'ungrouped'
    assert tasks['free']['project_id'] == 'ungrouped'
    assert tasks['assigned']['project_id'] == 'outer'


def test_missing_corrupt_metadata_preserves_observed_tasks(tmp_path):
    (tmp_path / '.codex-global-state.json').write_text('{broken')
    store = TaskEventStore(tmp_path/'events'); record(store)
    tasks = task_dashboard(store, codex_home=tmp_path, now=110)['tasks']
    assert len(tasks) == 1 and tasks[0]['status'] == 'running'
    assert tasks[0]['title'] is None
    assert tasks[0]['project'] == 'project'
    assert not (tmp_path / 'state_5.sqlite').exists()


def test_project_order_and_no_raw_paths_in_catalog_response(tmp_path):
    with catalog_db(tmp_path) as db:
        for i in range(3):
            db.execute('INSERT INTO projects VALUES (?,?,?)', (str(i), 'Project '+str(i), i))
            db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?)', ('s'+str(i), 'Title', None, str(i), '/private/work/'+str(i), 0, 50, 100))
    (tmp_path/'.codex-global-state.json').write_text(json.dumps({'pinned-project-ids':['2'],'project-order':['1','0']}))
    data = task_dashboard(TaskEventStore(tmp_path/'events'), codex_home=tmp_path, now=110)
    assert [t['project_id'] for t in data['tasks']] == ['2','1','0']
    assert '/private' not in json.dumps(data)


def test_deleted_tasks_do_not_return_from_old_observer_records(tmp_path):
    with catalog_db(tmp_path) as db:
        db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?)', ('kept', 'Kept', None, None, '/work', 0, 50, 100))
    store = TaskEventStore(tmp_path/'events'); record(store, session='deleted')
    assert [t['id'] for t in task_dashboard(store, codex_home=tmp_path, now=110)['tasks']] == ['kept']
    with sqlite3.connect(tmp_path/'state_5.sqlite') as db:
        db.execute('DELETE FROM threads')
    assert not task_dashboard(store, codex_home=tmp_path, now=110)['tasks']


def test_migrated_desktop_order_updates_without_restart_and_ignores_stale_json(tmp_path):
    with catalog_db(tmp_path) as db:
        for i in range(3):
            db.execute('INSERT INTO projects VALUES (?,?,?)', (str(i), 'Project '+str(i), i))
            db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?)', ('s'+str(i), 'Task', None, str(i), '/work/'+str(i), 0, 50, 100+i))
    state = {
        'app-server-projects-migration-by-host': {'local:' + str(tmp_path): {'projectsMigrated': True}},
        'app-server-project-id-by-legacy-project-id-by-host': {'local:' + str(tmp_path): {'old-2': '2'}},
        'local-projects': {'old-2': {'name': 'Outdated name', 'rootPaths': []}},
        'pinned-project-ids': ['deleted', 'old-2', '2'], 'project-order': ['1', '0'],
    }
    path = tmp_path / '.codex-global-state.json'
    path.write_text(json.dumps(state))
    store = TaskEventStore(tmp_path/'events')
    def projects():
        return [(t['project_id'], t['project']) for t in task_dashboard(store, codex_home=tmp_path)['tasks']]
    assert projects() == [('2', 'Project 2'), ('0', 'Project 0'), ('1', 'Project 1')]
    with sqlite3.connect(tmp_path/'state_5.sqlite') as db:
        db.execute("UPDATE projects SET position=-1, name='Renamed' WHERE id='1'")
    assert projects() == [('2', 'Project 2'), ('1', 'Renamed'), ('0', 'Project 0')]
    state['pinned-project-ids'] = []
    path.write_text(json.dumps(state))
    assert projects() == [('1', 'Renamed'), ('0', 'Project 0'), ('2', 'Project 2')]


def test_legacy_desktop_reorder_is_reread_on_every_request(tmp_path):
    with catalog_db(tmp_path) as db:
        for i in range(2):
            db.execute('INSERT INTO projects VALUES (?,?,?)', (str(i), 'Project '+str(i), i))
            db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?)', ('s'+str(i), 'Task', None, str(i), '/work', 0, 50, 100))
    store = TaskEventStore(tmp_path/'events')
    path = tmp_path / '.codex-global-state.json'
    for order in [['1', '0'], ['0', '1']]:
        path.write_text(json.dumps({'project-order': order}))
        assert [t['project_id'] for t in task_dashboard(store, codex_home=tmp_path)['tasks']] == order


def test_project_manifest_keeps_empty_projects_in_order_without_private_roots(tmp_path):
    with catalog_db(tmp_path) as db:
        for i in range(2):
            db.execute('INSERT INTO projects VALUES (?,?,?)', (str(i), 'Project '+str(i), i))
            db.execute('INSERT INTO project_roots VALUES (?,?,?)', (str(i), 0, '/private/'+str(i)))
    (tmp_path/'.codex-global-state.json').write_text(json.dumps({'project-order': ['1','0']}))
    data = task_dashboard(TaskEventStore(tmp_path/'events'), codex_home=tmp_path)
    assert data['projects'] == [{'id':'1','name':'Project 1'}, {'id':'0','name':'Project 0'}]
    assert data['tasks'] == []
    assert '/private' not in json.dumps(data)
