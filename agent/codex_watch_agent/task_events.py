"""Local task history and a durable, status-only push outbox.

Inspired by H1234L1/codex-watch-notifier (MIT). No prompts, tool arguments,
credentials, full paths or assistant replies are persisted or published.
"""
from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import time
import tempfile
import uuid
from urllib.parse import urlsplit

import httpx

DEFAULT_STATE = Path.home() / 'Library/Application Support/CodexQuotaWatch'
EVENT_STATUS = {'UserPromptSubmit': 'running', 'PermissionRequest': 'needs_approval', 'Stop': 'finished', 'Interrupt': 'interrupted'}
PUSH_TEXT = {
    'needs_approval': ('Codex 需要确认', '有一项操作正在等待你的确认，请返回 Codex 查看。'),
    'finished': ('Codex 本轮已结束', '本轮回复已结束，请打开 Codex 查看结果。'),
    'test': ('Codex 提醒测试', '通知通道已连通。锁定手机并佩戴手表，可验证手表提醒。'),
}


def state_dir() -> Path:
    return Path(os.environ.get('CODEX_QUOTA_STATE_DIR', str(DEFAULT_STATE))).expanduser()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class TaskEventStore:
    def __init__(self, root: Path | None = None):
        self.root = root or state_dir()
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path = self.root / 'task-events.sqlite3'
        with self.connection() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS turns (
                    id TEXT PRIMARY KEY, project TEXT NOT NULL, updated_at TEXT NOT NULL,
                    status TEXT NOT NULL, started_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS outbox (
                    id TEXT PRIMARY KEY, turn_id TEXT NOT NULL, status TEXT NOT NULL,
                    created REAL NOT NULL, due REAL NOT NULL, attempts INTEGER DEFAULT 0,
                    delivered_at TEXT, error TEXT, expired INTEGER DEFAULT 0);
            ''')
        self.path.chmod(0o600)

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=2)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def record(self, event: dict) -> bool:
        kind = event.get('hook_event_name')
        status = EVENT_STATUS.get(kind)
        # Ignore recursive Stop and subagent events to avoid duplicate alerts.
        if status is None or (kind == 'Stop' and event.get('stop_hook_active') is True):
            return False
        if event.get('agent_id') or event.get('agent_type'):
            return False
        session, turn = event.get('session_id'), event.get('turn_id')
        if not isinstance(session, str) or not session or not isinstance(turn, str) or not turn:
            return False
        key = hashlib.sha256(f'{session}\0{turn}'.encode()).hexdigest()[:24]
        cwd = event.get('cwd')
        project = re.split(r'[/\\]', cwd.rstrip('/\\'))[-1][:80] if isinstance(cwd, str) else ''
        project = ''.join(c for c in project if c.isprintable()) or 'Codex'
        now, timestamp = time.time(), utc_now()
        with self.connection() as db:
            previous = db.execute('SELECT * FROM turns WHERE id=?', (key,)).fetchone()
            if previous and (previous['status'] == 'interrupted' or (previous['status'] == 'finished' and kind != 'Stop')):
                return False
            db.execute('''INSERT INTO turns VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
                updated_at=excluded.updated_at, status=excluded.status''',
                (key, project, timestamp, status, timestamp))
            if status in PUSH_TEXT:
                # Distinct approvals in the same turn get separate alerts; retries of
                # the same request are idempotent. Raw tool inputs never leave memory.
                action = json.dumps(event.get('tool_input', {}), sort_keys=True) if status == 'needs_approval' else ''
                request_id = event.get('tool_use_id') or event.get('request_id') or action
                alert_id = hashlib.sha256(f'{key}\0{status}\0{request_id}'.encode()).hexdigest()
                db.execute('INSERT OR IGNORE INTO outbox(id,turn_id,status,created,due) VALUES(?,?,?,?,?)',
                           (alert_id, key, status, now, now))
            if status in ('finished', 'interrupted'):
                # An approval that was never delivered is no longer actionable.
                db.execute("UPDATE outbox SET expired=1 WHERE turn_id=? AND status='needs_approval' AND delivered_at IS NULL", (key,))
            db.execute('DELETE FROM outbox WHERE created < ?', (now - 7 * 86400,))
            db.execute('DELETE FROM turns WHERE id NOT IN (SELECT id FROM turns ORDER BY updated_at DESC LIMIT 100)')
        return True

    def test_notification(self):
        now = time.time()
        with self.connection() as db:
            db.execute('INSERT INTO outbox(id,turn_id,status,created,due) VALUES(?,?,?,?,?)',
                       (uuid.uuid4().hex, 'test', 'test', now, now))

    def snapshot(self) -> dict:
        config = load_notification_config(self.root)
        with self.connection() as db:
            events = [dict(row) for row in db.execute('SELECT * FROM turns ORDER BY updated_at DESC LIMIT 10')]
            delivered = db.execute('SELECT MAX(delivered_at) FROM outbox').fetchone()[0]
            pending = db.execute('SELECT COUNT(*) FROM outbox WHERE delivered_at IS NULL AND expired=0').fetchone()[0]
        return {'task_events': events, 'notifications': {
            'enabled': config.get('enabled') is True,
            'provider': config.get('provider', 'ntfy'),
            'server': 'https://api.day.app' if config.get('provider') == 'bark' else 'https://ntfy.sh',
            'topic': '' if config.get('provider') == 'bark' else config.get('topic', ''),
            'last_delivery_at': delivered,
            'pending_count': pending,
        }}


def load_notification_config(root: Path) -> dict:
    try:
        value = json.loads((root / 'notifications.json').read_text())
        if not isinstance(value, dict):
            return {}
        if value.get('provider') == 'bark':
            key = value.get('device_key')
            return value if isinstance(key, str) and re.fullmatch(r'[A-Za-z0-9_-]{8,128}', key) else {}
        if value.get('provider', 'ntfy') != 'ntfy':
            return {}
        topic = value.get('topic', '')
        if not isinstance(topic, str) or not re.fullmatch(r'codex-[a-f0-9]{32}', topic):
            return {}
        return value
    except (OSError, ValueError):
        return {}


def save_bark_config(value: str, root: Path | None = None):
    """Extract a key without ever requesting or persisting a pasted URL."""
    if not isinstance(value, str) or len(value) > 2048:
        raise ValueError('Invalid Bark address')
    key = value.strip()
    if '://' in key:
        url = urlsplit(key)
        if url.scheme != 'https' or url.netloc != 'api.day.app' or url.query or url.fragment:
            raise ValueError('Invalid Bark address')
        key = next(iter(url.path.split('/')[1:2]), '')
    if not re.fullmatch(r'[A-Za-z0-9_-]{8,128}', key):
        raise ValueError('Invalid Bark address')
    root = root or state_dir()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(prefix='.notifications-', dir=root)
    try:
        with os.fdopen(fd, 'w') as file:
            json.dump({'enabled': True, 'provider': 'bark', 'device_key': key}, file)
        os.replace(name, root / 'notifications.json')
    finally:
        if os.path.exists(name):
            os.unlink(name)


def deliver_pending(store: TaskEventStore, *, client=None, now: float | None = None) -> int:
    """Single worker retries transient errors, with a 15 minute delivery deadline."""
    config = load_notification_config(store.root)
    if config.get('enabled') is not True:
        return 0
    now = time.time() if now is None else now
    with store.connection() as db:
        db.execute('UPDATE outbox SET expired=1 WHERE delivered_at IS NULL AND created < ?', (now - 900,))
        rows = db.execute('SELECT * FROM outbox WHERE delivered_at IS NULL AND expired=0 AND due<=? ORDER BY created LIMIT 10', (now,)).fetchall()
    if client is None:
        with httpx.Client(timeout=8, trust_env=False, follow_redirects=False) as session:
            return _deliver(store, config, rows, session, now)
    return _deliver(store, config, rows, client, now)


def _deliver(store, config, rows, client, now):
    sent = 0
    for row in rows:
        title, message = PUSH_TEXT[row['status']]
        # Fixed destination and allowlisted status text only. No event fields in payload.
        bark = config.get('provider') == 'bark'
        if bark:
            url = 'https://api.day.app/push'
            payload = {'device_key': config['device_key'], 'title': title, 'body': message,
                       'group': 'Codex', 'sound': 'silence', 'level': 'active'}
        else:
            url = 'https://ntfy.sh'
            payload = {'topic': config['topic'], 'title': title, 'message': message,
                       'priority': 4 if row['status'] == 'needs_approval' else 3,
                       'tags': ['warning' if row['status'] == 'needs_approval' else 'white_check_mark']}
        try:
            response = client.post(url, json=payload)
            response.raise_for_status()
            result = response.json()
            if not isinstance(result, dict) or (result.get('code') != 200 if bark else not result.get('id')):
                raise ValueError('Invalid push receipt')
        except (httpx.HTTPError, ValueError):
            attempts = row['attempts'] + 1
            with store.connection() as db:
                db.execute('UPDATE outbox SET attempts=?,due=?,error=? WHERE id=?',
                           (attempts, now + min(300, 10 * 2 ** min(attempts, 5)), '暂时无法发送，稍后重试', row['id']))
        else:
            with store.connection() as db:
                db.execute('UPDATE outbox SET delivered_at=?,error=NULL WHERE id=?', (utc_now(), row['id']))
            sent += 1
    return sent


def run_worker():
    os.umask(0o077)
    store = TaskEventStore()
    while True:
        try:
            deliver_pending(store)
        except Exception:
            # Avoid dumping event data or credentials to launchd logs.
            print('Notification worker will retry.', flush=True)
        time.sleep(2)


if __name__ == '__main__':
    run_worker()
