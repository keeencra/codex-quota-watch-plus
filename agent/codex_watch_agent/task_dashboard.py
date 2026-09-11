"""Authenticated task overview. Titles are read locally, never sent to push/widgets."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sqlite3
import time

PHASES = {
    'running': '正在处理任务', 'needs_approval': '等待操作确认',
    'needs_input': '等待你的回复', 'stalled': '暂未检测到新活动',
    'finished': '本轮处理已结束', 'interrupted': '任务已中断',
}
ACTIVITIES = {'started': '开始处理', 'thinking': '正在分析', 'tool': '正在执行工具',
              'tool_result': '已收到工具结果', 'responding': '正在整理回复'}


def record_progress(db, key, session, status, timestamp, activity=None):
    phase = ACTIVITIES.get(activity, PHASES.get(status, '状态待确认')) if status == 'running' else PHASES.get(status, '状态待确认')
    previous = db.execute('SELECT recent FROM task_progress WHERE id=?', (key,)).fetchone()
    recent = json.loads(previous['recent']) if previous else []
    if not recent or recent[0]['text'] != phase:
        recent.insert(0, {'text': phase, 'at': timestamp})
    db.execute('INSERT OR REPLACE INTO task_progress VALUES (?,?,?,?,?)',
               (key, session, phase, json.dumps(recent[:5], ensure_ascii=False), timestamp))


def task_dashboard(store, *, codex_home=None, now=None):
    now = time.time() if now is None else now
    home = Path(codex_home or os.environ.get('CODEX_HOME', Path.home() / '.codex')).expanduser().resolve()
    with store.connection() as db:
        rows = db.execute('''SELECT t.*, p.session, p.phase, p.recent FROM turns t
            LEFT JOIN task_progress p ON p.id=t.id ORDER BY t.updated_at DESC''').fetchall()
    # One most recent turn per known task. Legacy rows keep their own identity.
    seen, tasks = set(), []
    title_db = None
    try:
        title_db = sqlite3.connect((home / 'state_5.sqlite').as_uri() + '?mode=ro', uri=True, timeout=1)
    except (sqlite3.Error, ValueError):
        pass
    try:
        for row in rows:
            identity = row['session'] or row['id']
            if identity in seen:
                continue
            seen.add(identity)
            title = None
            if title_db and row['session']:
                try:
                    match = title_db.execute('SELECT title FROM threads WHERE id=?', (row['session'],)).fetchone()
                    if match and isinstance(match[0], str):
                        title = ''.join(c for c in match[0] if c.isprintable()).strip()[:160] or None
                except sqlite3.Error:
                    pass
            age = now - datetime.fromisoformat(row['updated_at']).timestamp()
            stale = row['status'] in ('running', 'needs_approval', 'needs_input', 'stalled') and age > 900
            tasks.append({
                'id': row['id'], 'project': row['project'], 'title': title,
                'status': row['status'], 'phase': row['phase'] or PHASES.get(row['status'], '状态待确认'),
                'updated_at': row['updated_at'], 'started_at': row['started_at'],
                'stale': stale, 'recent': json.loads(row['recent']) if row['recent'] else [],
            })
    finally:
        if title_db:
            title_db.close()
    return {'updated_at': datetime.fromtimestamp(now, timezone.utc).isoformat(), 'tasks': tasks}
