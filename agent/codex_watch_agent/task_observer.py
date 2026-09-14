"""Incremental rollout fallback. Never replays history on first installation.

Original implementation: stores file offsets and status metadata only, no
conversation text. Logs can report events, but can never authorize a command.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import time

from .task_events import TaskEventStore


class TaskObserver:
    def __init__(self, store: TaskEventStore, codex_home=None):
        self.store = store
        self.home = Path(codex_home or os.environ.get('CODEX_HOME', Path.home() / '.codex')).expanduser()
        with store.connection() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS observer_meta (key TEXT PRIMARY KEY, value REAL);
                CREATE TABLE IF NOT EXISTS observer_files (key TEXT PRIMARY KEY, inode INTEGER, offset INTEGER, session TEXT, turn TEXT, project TEXT, child INTEGER);
                CREATE TABLE IF NOT EXISTS observer_activity (key TEXT PRIMARY KEY, session TEXT, turn TEXT, project TEXT, last REAL, warned INTEGER DEFAULT 0);
            ''')
            if 'discarding' not in {row['name'] for row in db.execute('PRAGMA table_info(observer_files)')}:
                db.execute('ALTER TABLE observer_files ADD COLUMN discarding INTEGER NOT NULL DEFAULT 0')

    def scan(self, now=None):
        now = time.time() if now is None else now
        # Archived rollouts can be moved or copied with a new path. They are
        # history, never evidence of a currently running task.
        paths = [p for p in (self.home / 'sessions').rglob('*.jsonl') if not p.is_symlink()]
        with self.store.connection() as db:
            initialized = db.execute("SELECT value FROM observer_meta WHERE key='started'").fetchone()
            if initialized is None:
                for p in paths:
                    try:
                        stat = p.stat()
                        db.execute('INSERT OR IGNORE INTO observer_files VALUES (?,?,?,?,?,?,?,0)', (self.file_key(p), stat.st_ino, stat.st_size, '', '', '', 0))
                    except OSError:
                        pass
                db.execute("INSERT INTO observer_meta VALUES ('started',?)", (now,))
                return
        for p in paths:
            try:
                self.read_file(p, now, initialized['value'])
            except (OSError, ValueError, TypeError, KeyError):
                # A malformed/local file must not stop the notification worker.
                continue
        live_sessions, catching_up = set(), set()
        with self.store.connection() as db:
            for path in paths:
                row = db.execute('SELECT session, offset FROM observer_files WHERE key=?', (self.file_key(path),)).fetchone()
                if not row or not row['session']:
                    continue
                try:
                    size = path.stat().st_size
                except OSError:
                    continue
                live_sessions.add(row['session'])
                if row['offset'] < size:
                    catching_up.add(row['session'])
            # Remove abandoned archive timers and invalidate their queued alerts.
            for row in db.execute('SELECT key, session FROM observer_activity').fetchall():
                if row['session'] not in live_sessions:
                    db.execute('DELETE FROM observer_activity WHERE key=?', (row['key'],))
            for row in db.execute("SELECT o.id, p.session FROM outbox o LEFT JOIN task_progress p ON p.id=o.turn_id WHERE o.status='stalled' AND o.delivered_at IS NULL AND o.expired=0").fetchall():
                if row['session'] not in live_sessions or row['session'] in catching_up:
                    db.execute('UPDATE outbox SET expired=1 WHERE id=?', (row['id'],))
        self.check_stalled(now, live_sessions - catching_up)

    @staticmethod
    def file_key(path):
        return hashlib.sha256(str(path).encode()).hexdigest()

    def read_file(self, path, now, started):
        stat = path.stat()
        key = self.file_key(path)
        with self.store.connection() as db:
            previous = db.execute('SELECT * FROM observer_files WHERE key=?', (key,)).fetchone()
        if previous and previous['inode'] == stat.st_ino and previous['offset'] == stat.st_size:
            return
        offset = previous['offset'] if previous and previous['inode'] == stat.st_ino and previous['offset'] <= stat.st_size else 0
        discarding = bool(previous['discarding']) if previous and offset else False
        with path.open('rb') as file:
            meta_line = file.readline(256 * 1024)
            meta = json.loads(meta_line).get('payload', {})
            if not isinstance(meta, dict):
                return
            session = str(meta.get('session_id') or meta.get('id') or '')
            project = Path(str(meta.get('cwd') or 'Codex')).name
            child = bool(meta.get('agent_id') or meta.get('agent_type') or 'subagent' in str(meta.get('source', '')).lower())
            turn = previous['turn'] if previous and previous['inode'] == stat.st_ino else ''
            file.seek(offset)
            # Bound each pass. Incomplete lines stay unread until the next scan.
            raw = file.read(2 * 1024 * 1024)
            # Tool results (especially images) can exceed a whole scan budget.
            # Skip them in bounded chunks instead of getting stuck forever.
            if discarding:
                end = raw.find(b'\n')
                if end < 0:
                    offset += len(raw)
                    raw = b''
                else:
                    offset += end + 1
                    raw = raw[end + 1:]
                    discarding = False
            complete = raw.rfind(b'\n') + 1
            if not complete and len(raw) == 2 * 1024 * 1024:
                offset += len(raw)
                raw = b''
                discarding = True
            for line in raw[:complete].splitlines():
                try:
                    record = json.loads(line)
                    payload = record.get('payload', {})
                    if not isinstance(payload, dict):
                        continue
                    if payload.get('turn_id'):
                        turn = str(payload['turn_id'])
                    stamp = record.get('timestamp')
                    observed = datetime.fromisoformat(str(stamp).replace('Z', '+00:00')).timestamp()
                    if child or not session or not turn or observed < started or observed > now + 60:
                        continue
                    self.observe(record, session, turn, project, observed)
                except (ValueError, TypeError, AttributeError):
                    continue
        with self.store.connection() as db:
            db.execute('INSERT OR REPLACE INTO observer_files VALUES (?,?,?,?,?,?,?,?)', (key, stat.st_ino, offset + complete, session, turn, project, child, int(discarding)))

    def observe(self, record, session, turn, project, stamp):
        payload = record['payload']
        kind, record_type = payload.get('type'), record.get('type')
        event = {'session_id': session, 'turn_id': turn, 'cwd': project}
        key = hashlib.sha256(f'{session}\0{turn}'.encode()).hexdigest()[:24]
        status_event = None
        if kind == 'task_complete':
            status_event = 'Stop'
        elif kind in ('turn_aborted', 'task_aborted', 'interrupted'):
            status_event = 'Interrupt'
        elif kind in ('permission_request', 'approval_request'):
            # Observed approvals lack a live reply channel. Report only; never
            # turn log content into an approvable request.
            status_event = 'NeedsInput'
        elif record_type == 'response_item' and kind == 'function_call' and str(payload.get('name', '')).split('.')[-1] in ('request_user_input', 'request_user_input_async'):
            status_event = 'NeedsInput'
        elif kind == 'task_started' or record_type == 'response_item':
            status_event = 'Activity'
        if status_event is None:
            return
        if status_event in ('Activity', 'NeedsInput'):
            with self.store.connection() as db:
                current = db.execute('SELECT started_at FROM turns WHERE id=?', (key,)).fetchone()
                started = current['started_at'] if current else datetime.fromtimestamp(stamp, timezone.utc).isoformat()
                newer = db.execute('''SELECT 1 FROM turns t JOIN task_progress p ON p.id=t.id
                    WHERE p.session=? AND t.id<>? AND t.started_at>? LIMIT 1''', (session, key, started)).fetchone()
                if newer:
                    # Rotated/copied files can arrive out of order. A previous
                    # turn must not become current again after a newer turn.
                    db.execute('DELETE FROM observer_activity WHERE key=?', (key,))
                    db.execute("UPDATE outbox SET expired=1 WHERE turn_id=? AND status IN ('stalled','needs_input') AND delivered_at IS NULL", (key,))
                    return
        event['hook_event_name'] = status_event
        event['activity'] = {'task_started': 'started', 'reasoning': 'thinking',
                             'function_call': 'tool', 'custom_tool_call': 'tool',
                             'function_call_output': 'tool_result', 'custom_tool_call_output': 'tool_result',
                             'message': 'responding'}.get(kind)
        if status_event == 'NeedsInput':
            event['request_id'] = str(payload.get('call_id') or payload.get('id') or turn)
        if not self.store.record(event, occurred_at=stamp):
            return
        with self.store.connection() as db:
            if status_event in ('Stop', 'Interrupt', 'NeedsInput'):
                db.execute('DELETE FROM observer_activity WHERE key=?', (key,))
            else:
                # A new turn supersedes timers from older turns in this session.
                older = db.execute('SELECT key FROM observer_activity WHERE session=? AND key<>? AND last<=?', (session, key, stamp)).fetchall()
                for row in older:
                    db.execute('DELETE FROM observer_activity WHERE key=?', (row['key'],))
                    db.execute("UPDATE outbox SET expired=1 WHERE turn_id=? AND status='stalled' AND delivered_at IS NULL", (row['key'],))
                db.execute('''INSERT INTO observer_activity VALUES (?,?,?,?,?,0) ON CONFLICT(key) DO UPDATE SET
                    last=MAX(observer_activity.last,excluded.last), warned=CASE WHEN excluded.last>observer_activity.last THEN 0 ELSE observer_activity.warned END''', (key, session, turn, project, stamp))
        if status_event in ('Stop', 'Interrupt'):
            from .approvals import ApprovalStore
            ApprovalStore(self.store.root).cancel_turn(event)

    def check_stalled(self, now, live_sessions):
        with self.store.connection() as db:
            rows = db.execute('''SELECT a.* FROM observer_activity a JOIN turns t ON t.id=a.key
                WHERE a.warned=0 AND a.last<=? AND t.status='running' ''', (now - 600,)).fetchall()
        for row in rows:
            if row['session'] not in live_sessions:
                continue
            self.store.record({'hook_event_name': 'Stalled', 'session_id': row['session'], 'turn_id': row['turn'], 'cwd': row['project']}, occurred_at=now)
            with self.store.connection() as db:
                db.execute('UPDATE observer_activity SET warned=1 WHERE key=?', (row['key'],))
