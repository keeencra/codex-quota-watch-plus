"""Single-request decisions for a live PermissionRequest hook.

Never executes commands. Only the waiting hook can consume a decision and
return it to Codex. Expired/disconnected requests fall back to local approval.
"""
from __future__ import annotations

import hashlib
import json
import secrets
import time

from .task_events import TaskEventStore, state_dir


class ApprovalConflict(ValueError):
    pass


class ApprovalStore(TaskEventStore):
    def __init__(self, root=None):
        self.root = root or state_dir()
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path = self.root / 'approvals.sqlite3'
        with self.connection() as db:
            db.execute('PRAGMA secure_delete=ON')
            db.execute('''CREATE TABLE IF NOT EXISTS approvals (
                id TEXT PRIMARY KEY, turn_key TEXT NOT NULL, nonce TEXT NOT NULL,
                fingerprint TEXT NOT NULL, project TEXT NOT NULL, tool TEXT NOT NULL,
                details TEXT NOT NULL, created REAL NOT NULL, expires REAL NOT NULL,
                heartbeat REAL NOT NULL, status TEXT NOT NULL, decision TEXT)''')
        self.path.chmod(0o600)

    def enabled(self):
        try:
            return json.loads((self.root / 'remote-approval.json').read_text()).get('enabled') is True
        except (OSError, ValueError, AttributeError):
            return False

    def create(self, event, now=None, ttl=180):
        now = time.time() if now is None else now
        if event.get('hook_event_name') != 'PermissionRequest' or event.get('agent_id') or event.get('agent_type'):
            raise ValueError('Unsupported request')
        session, turn, tool = (event.get(k) for k in ('session_id', 'turn_id', 'tool_name'))
        if not all(isinstance(v, str) and v for v in (session, turn, tool)):
            raise ValueError('Incomplete request')
        raw = event.get('tool_input')
        if not isinstance(raw, dict) or not raw:
            raise ValueError('Missing operation details')
        # Preserve every argument and the working directory; never approve a
        # truncated/redacted preview of a different underlying operation.
        details = json.dumps({'cwd': event.get('cwd', ''), 'arguments': raw}, ensure_ascii=False, indent=2, sort_keys=True)
        if len(details.encode()) > 16384 or any(ord(c) < 32 and c not in '\n\t\r' for c in details):
            raise ValueError('Review on Mac required')
        request_id, nonce = secrets.token_urlsafe(24), secrets.token_urlsafe(32)
        fingerprint = hashlib.sha256((tool + '\0' + details).encode()).hexdigest()
        turn_key = hashlib.sha256(f'{session}\0{turn}'.encode()).hexdigest()[:24]
        from pathlib import Path
        project = Path(str(event.get('cwd') or 'Codex')).name[:80] or 'Codex'
        with self.connection() as db:
            db.execute('DELETE FROM approvals WHERE expires < ?', (now - 86400,))
            db.execute('INSERT INTO approvals VALUES (?,?,?,?,?,?,?,?,?,?,?,NULL)',
                       (request_id, turn_key, nonce, fingerprint, project, tool, details, now, now + min(180, ttl), now, 'pending'))
        return self.get(request_id, now)

    @staticmethod
    def _expire(db, now):
        db.execute("UPDATE approvals SET status='expired', details='' WHERE status IN ('pending','submitted') AND (expires<=? OR heartbeat<?)", (now, now - 8))

    def pending(self, now=None):
        now = time.time() if now is None else now
        with self.connection() as db:
            self._expire(db, now)
            return [dict(r) for r in db.execute("SELECT * FROM approvals WHERE status='pending' ORDER BY created DESC LIMIT 20")]

    def get(self, request_id, now=None):
        now = time.time() if now is None else now
        with self.connection() as db:
            self._expire(db, now)
            row = db.execute('SELECT * FROM approvals WHERE id=?', (request_id,)).fetchone()
        if row is None:
            raise ApprovalConflict('Request unavailable')
        return dict(row)

    def decide(self, request_id, nonce, fingerprint, decision, now=None):
        if decision not in ('allow', 'deny'):
            raise ValueError('Only a single-request decision is supported')
        now = time.time() if now is None else now
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            self._expire(db, now)
            row = db.execute('SELECT * FROM approvals WHERE id=?', (request_id,)).fetchone()
            if row is None or not secrets.compare_digest(row['nonce'], nonce) or not secrets.compare_digest(row['fingerprint'], fingerprint):
                raise ApprovalConflict('Request changed or unavailable')
            if row['status'] in ('submitted', 'consumed') and row['decision'] == decision:
                return row['status']
            if row['status'] != 'pending':
                raise ApprovalConflict('Request no longer pending')
            db.execute("UPDATE approvals SET status='submitted', decision=? WHERE id=?", (decision, request_id))
        return 'submitted'

    def tick(self, request_id, now=None, consume=True):
        now = time.time() if now is None else now
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            self._expire(db, now)
            row = db.execute('SELECT * FROM approvals WHERE id=?', (request_id,)).fetchone()
            if row is None or row['status'] not in ('pending', 'submitted'):
                return 'closed'
            db.execute('UPDATE approvals SET heartbeat=? WHERE id=?', (now, request_id))
            if row['status'] == 'submitted':
                if consume:
                    db.execute("UPDATE approvals SET status='consumed', details='' WHERE id=?", (request_id,))
                return row['decision']
        return None

    def acknowledge(self, request_id):
        with self.connection() as db:
            db.execute("UPDATE approvals SET status='consumed', details='' WHERE id=? AND status='submitted'", (request_id,))

    def cancel_turn(self, event):
        key = hashlib.sha256(f"{event.get('session_id')}\0{event.get('turn_id')}".encode()).hexdigest()[:24]
        with self.connection() as db:
            db.execute("UPDATE approvals SET status='cancelled', details='' WHERE turn_key=? AND status IN ('pending','submitted')", (key,))

    def close(self, request_id):
        with self.connection() as db:
            db.execute("UPDATE approvals SET status='expired', details='' WHERE id=? AND status IN ('pending','submitted')", (request_id,))


def await_decision(event, store=None):
    store = store or ApprovalStore(state_dir())
    if not store.enabled():
        return {}
    request = store.create(event)
    try:
        while True:
            if not store.enabled():
                return {}
            decision = store.tick(request['id'])
            if decision == 'closed':
                return {}
            if decision in ('allow', 'deny'):
                return {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {
                    'behavior': decision, **({'message': 'User declined this operation remotely.'} if decision == 'deny' else {})}}}
            time.sleep(0.5)
    finally:
        store.close(request['id'])
