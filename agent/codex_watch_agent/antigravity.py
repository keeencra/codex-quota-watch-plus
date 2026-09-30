"""Experimental, read-only bridge for the official AGY CLI statusLine payload.

Never opens credentials, transcripts, or the Antigravity private backend. Task
states are observations, not completion events or approval capabilities.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import shlex
import sqlite3
import sys
import time

from .task_events import state_dir

MAX_BYTES = 128 * 1024
STALE_SECONDS = 900
STATES = {"idle", "thinking", "working", "tool_use", "initializing"}


def label(value, limit=80):
    if not isinstance(value, str):
        return ""
    return ''.join(c for c in value if c.isprintable())[:limit]


def normalize(payload, now=None):
    if not isinstance(payload, dict) or payload.get('product') != 'antigravity':
        raise ValueError('Expected an Antigravity statusLine object')
    session = payload.get('conversation_id') or payload.get('session_id')
    if not isinstance(session, str) or not session or len(session) > 256:
        raise ValueError('Missing conversation identifier')
    quotas = []
    raw = payload.get('quota', {})
    if isinstance(raw, dict):
        for key, item in list(raw.items())[:64]:
            if not isinstance(item, dict):
                continue
            value = item.get('remaining_fraction')
            if type(value) not in (int, float) or not 0 <= value <= 1 or not math.isfinite(value):
                continue
            reset = None
            try:
                date = datetime.fromisoformat(item['reset_time'].replace('Z', '+00:00'))
                if date.tzinfo is not None:
                    reset = date.astimezone(timezone.utc).isoformat()
            except (KeyError, TypeError, ValueError, AttributeError):
                pass
            quotas.append({'name': label(key), 'remaining': value, 'reset': reset})
    model = payload.get('model')
    model = model if isinstance(model, dict) else {}
    state = payload.get('agent_state')
    return {
        'id': hashlib.sha256(session.encode()).hexdigest()[:24],
        'observed_at': time.time() if now is None else now,
        'state': state if isinstance(state, str) and state in STATES else 'unknown',
        'needs_confirmation': payload.get('tool_confirmation_pending') is True,
        'model': label(model.get('display_name') or model.get('id')),
        'quotas': quotas,
    }


class AntigravityStore:
    def __init__(self, root=None):
        self.path = (root or state_dir()).expanduser().resolve() / 'antigravity-status.sqlite3'

    def ingest(self, payload, now=None):
        row = normalize(payload, now)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # Create with private permissions before SQLite opens the file.
        self.path.touch(mode=0o600, exist_ok=True)
        self.path.chmod(0o600)
        with sqlite3.connect(self.path, timeout=2) as db:
            db.execute('CREATE TABLE IF NOT EXISTS observations (id TEXT PRIMARY KEY, observed REAL, payload TEXT)')
            db.execute('INSERT OR REPLACE INTO observations VALUES (?, ?, ?)',
                       (row['id'], row['observed_at'], json.dumps(row, allow_nan=False)))
            db.execute('DELETE FROM observations WHERE id NOT IN (SELECT id FROM observations ORDER BY observed DESC LIMIT 50)')
        return row

    def snapshot(self, now=None):
        result = {'schema_version': 1, 'status': 'not_connected', 'sessions': [],
                  'capabilities': {'quota': True, 'task_status': True, 'reply': False,
                                   'approval': False, 'balance': False, 'notifications': False}}
        if not self.path.exists():
            return result
        try:
            with sqlite3.connect(f'{self.path.as_uri()}?mode=ro', uri=True, timeout=1) as db:
                rows = db.execute('SELECT payload FROM observations ORDER BY observed DESC LIMIT 50').fetchall()
            current = time.time() if now is None else now
            for (raw,) in rows:
                row = json.loads(raw)
                age = current - row['observed_at']
                row['stale'] = age < -60 or age >= STALE_SECONDS
                result['sessions'].append(row)
            if result['sessions']:
                result['status'] = 'stale' if all(r['stale'] for r in result['sessions']) else 'available'
        except (OSError, sqlite3.Error, ValueError, KeyError, TypeError):
            result['sessions'] = []
            result['status'] = 'unavailable'
        return result


def install(settings_path):
    """Explicit opt-in; preserve unrelated settings and refuse custom commands."""
    path = settings_path.expanduser()
    data = json.loads(path.read_text()) if path.exists() else {}
    command = shlex.join([sys.executable, '-m', 'codex_watch_agent.antigravity', 'ingest'])
    if not isinstance(data, dict):
        raise ValueError('Settings must be an object')
    old = data.get('statusLine')
    if old is not None and (not isinstance(old, dict) or old.get('command') != command):
        raise ValueError('Existing statusLine configuration; follow the manual integration guide')
    backup = path.with_name(path.name + '.codecompanion-backup')
    if path.exists() and not backup.exists():
        with backup.open('x') as output:
            backup.chmod(0o600)
            output.write(path.read_text())
    data['statusLine'] = {'type': 'command', 'command': command, 'stack_with_default': True, 'enabled': True}
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.codecompanion-tmp')
    with temporary.open('w') as output:
        temporary.chmod(0o600)
        json.dump(data, output, ensure_ascii=False, indent=2)
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['ingest', 'diagnose', 'install'])
    args = parser.parse_args()
    try:
        if args.command == 'install':
            install(Path.home() / '.gemini/antigravity-cli/settings.json')
            print('Antigravity CLI statusLine bridge configured. Restart the CLI to apply.')
        elif args.command == 'diagnose':
            snap = AntigravityStore().snapshot()
            # No IDs, text, account identity, paths, dates or actual quota values.
            print(json.dumps({'schema_version': 1, 'status': snap['status'],
                              'session_count': len(snap['sessions']),
                              'quota_entry_count': sum(len(s['quotas']) for s in snap['sessions']),
                              'capabilities': snap['capabilities']}))
        else:
            raw = sys.stdin.buffer.read(MAX_BYTES + 1)
            if len(raw) > MAX_BYTES:
                raise ValueError('Input too large')
            AntigravityStore().ingest(json.loads(raw))
            print('码伴 · 状态已同步')
    except Exception:
        # StatusLine runs in a user's terminal; never echo payloads or secrets.
        print('码伴 · 接入未完成，请检查配置' if args.command == 'ingest' else
              'Operation failed. Check configuration; an existing statusLine is not overwritten.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
