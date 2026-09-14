import json
from datetime import datetime,timezone
from codex_watch_agent.task_observer import TaskObserver
from codex_watch_agent.task_events import TaskEventStore


def line(kind, t, record_type='event_msg', **extra):
    return json.dumps({'type':record_type,'timestamp':datetime.fromtimestamp(t,timezone.utc).isoformat(),
                       'payload':{'type':kind,'turn_id':'turn',**extra}})+'\n'


def setup(tmp_path, child=False):
    home=tmp_path/'codex';(home/'sessions').mkdir(parents=True)
    path=home/'sessions'/'test.jsonl'
    path.write_text(json.dumps({'type':'session_meta','payload':{'id':'session','cwd':'/private/project','source':'subagent' if child else 'cli'}})+'\n')
    store=TaskEventStore(tmp_path/'state');observer=TaskObserver(store,home)
    return path,store,observer


def append(path,text):
    with path.open('a') as f:f.write(text)


def test_first_scan_does_not_replay_history_and_later_completion_deduplicates(tmp_path):
    path,store,observer=setup(tmp_path)
    append(path,line('task_complete',90));observer.scan(100)
    assert store.snapshot()['task_events']==[]
    append(path,line('task_started',110)+line('task_complete',120));observer.scan(130)
    assert store.snapshot()['task_events'][0]['status']=='finished'
    store.record({'session_id':'session','turn_id':'turn','cwd':'project','hook_event_name':'Stop'})
    observer.scan(140)
    with store.connection() as db:assert db.execute('SELECT count(*) FROM outbox').fetchone()[0]==1


def test_stall_once_recovers_on_activity_and_never_warns_after_finish(tmp_path):
    path,store,observer=setup(tmp_path);observer.scan(100)
    append(path,line('task_started',110));observer.scan(111);observer.scan(711);observer.scan(720)
    assert store.snapshot()['task_events'][0]['status']=='stalled'
    with store.connection() as db:assert db.execute('SELECT count(*) FROM outbox').fetchone()[0]==1
    append(path,line('function_call_output',730,'response_item',output='SECRET'));observer.scan(731)
    assert store.snapshot()['task_events'][0]['status']=='running'
    append(path,line('task_complete',740));observer.scan(741);observer.scan(2000)
    assert store.snapshot()['task_events'][0]['status']=='finished'
    assert 'SECRET' not in store.path.read_bytes().decode(errors='ignore')


def test_partial_lines_are_retried_and_subagents_ignored(tmp_path):
    path,store,observer=setup(tmp_path);observer.scan(100)
    message=line('task_started',110)
    append(path,message[:20]);observer.scan(120)
    assert store.snapshot()['task_events']==[]
    append(path,message[20:]);observer.scan(121)
    assert store.snapshot()['task_events'][0]['status']=='running'
    other=tmp_path/'other';other.mkdir()
    path,store,observer=setup(other,True);observer.scan(100)
    append(path,line('task_complete',110));observer.scan(120)
    assert store.snapshot()['task_events']==[]


def test_input_request_not_approvable_and_not_stalled(tmp_path):
    path,store,observer=setup(tmp_path);observer.scan(100)
    append(path,line('task_started',110)+line('function_call',115,'response_item',name='request_user_input',call_id='call'))
    observer.scan(120);observer.scan(900)
    assert store.snapshot()['task_events'][0]['status']=='needs_input'
    from codex_watch_agent.approvals import ApprovalStore
    assert ApprovalStore(store.root).pending()==[]


def test_oversized_tool_result_does_not_block_later_progress(tmp_path):
    path,store,observer=setup(tmp_path);observer.scan(100)
    append(path,line('task_started',110))
    observer.scan(111)
    append(path,line('custom_tool_call_output',112,'response_item',output='x'*(5*1024*1024)))
    append(path,line('reasoning',113,'response_item'))
    for now in (120,121,122,123):observer.scan(now)
    from codex_watch_agent.task_dashboard import task_dashboard
    task=task_dashboard(store,codex_home=tmp_path,now=124)['tasks'][0]
    assert task['phase']=='正在分析'
    with store.connection() as db:
        row=db.execute('SELECT offset,discarding FROM observer_files').fetchone()
        assert row['offset']==path.stat().st_size
        assert row['discarding']==0


def test_archiving_does_not_replay_history_or_keep_stall_timer(tmp_path):
    path,store,observer=setup(tmp_path);observer.scan(100)
    append(path,line('task_started',110));observer.scan(120)
    archived=observer.home/'archived_sessions';archived.mkdir()
    path.rename(archived/path.name)
    observer.scan(1000)
    with store.connection() as db:
        assert db.execute('SELECT count(*) FROM outbox').fetchone()[0]==0
        assert db.execute('SELECT count(*) FROM observer_activity').fetchone()[0]==0
    observer.scan(2000)
    with store.connection() as db:
        assert db.execute('SELECT count(*) FROM outbox').fetchone()[0]==0


def test_backlog_cannot_stall_before_later_completion_is_read(tmp_path):
    path,store,observer=setup(tmp_path);observer.scan(100)
    append(path,line('task_started',110))
    append(path,line('custom_tool_call_output',120,'response_item',output='x'*(5*1024*1024)))
    append(path,line('task_complete',130))
    for now in (1000,1010,1020,1030,1040):
        observer.scan(now)
        with store.connection() as db:
            assert db.execute("SELECT count(*) FROM outbox WHERE status='stalled'").fetchone()[0]==0
    assert store.snapshot()['task_events'][0]['status']=='finished'


def test_real_end_discovered_after_timeout_is_not_rejected(tmp_path):
    path,store,observer=setup(tmp_path);observer.scan(100)
    append(path,line('task_started',110));observer.scan(111);observer.scan(800)
    assert store.snapshot()['task_events'][0]['status']=='stalled'
    append(path,line('task_complete',120));observer.scan(810)
    assert store.snapshot()['task_events'][0]['status']=='finished'
    with store.connection() as db:
        assert db.execute("SELECT expired FROM outbox WHERE status='stalled'").fetchone()[0]==1


def test_new_turn_retires_old_timer_without_completion_event(tmp_path):
    path,store,observer=setup(tmp_path);observer.scan(100)
    append(path,line('task_started',110));observer.scan(120)
    append(path,line('task_started',200,turn_id='new'));observer.scan(210)
    with store.connection() as db:
        assert [r['turn'] for r in db.execute('SELECT turn FROM observer_activity')]==['new']
    observer.scan(750)
    with store.connection() as db:
        assert db.execute("SELECT count(*) FROM outbox WHERE status='stalled'").fetchone()[0]==0


def test_old_turn_from_another_rollout_cannot_restart_after_newer_end(tmp_path):
    path,store,observer=setup(tmp_path);observer.scan(100)
    observer.observe(json.loads(line('task_started',200,turn_id='new')), 'session','new','project',200)
    observer.observe(json.loads(line('task_complete',220,turn_id='new')), 'session','new','project',220)
    observer.observe(json.loads(line('reasoning',150,'response_item')), 'session','turn','project',150)
    observer.check_stalled(1000, {'session'})
    with store.connection() as db:
        assert db.execute('SELECT count(*) FROM observer_activity').fetchone()[0]==0
        assert db.execute("SELECT count(*) FROM outbox WHERE status='stalled'").fetchone()[0]==0


def test_late_old_tool_result_after_newer_turn_does_not_restart_timer(tmp_path):
    path,store,observer=setup(tmp_path);observer.scan(100)
    observer.observe(json.loads(line('task_started',110)), 'session','turn','project',110)
    observer.observe(json.loads(line('task_started',200,turn_id='new')), 'session','new','project',200)
    observer.observe(json.loads(line('task_complete',220,turn_id='new')), 'session','new','project',220)
    observer.observe(json.loads(line('function_call_output',300,'response_item')), 'session','turn','project',300)
    observer.check_stalled(1000, {'session'})
    with store.connection() as db:
        assert db.execute('SELECT count(*) FROM observer_activity').fetchone()[0]==0
        assert db.execute("SELECT count(*) FROM outbox WHERE status='stalled'").fetchone()[0]==0
