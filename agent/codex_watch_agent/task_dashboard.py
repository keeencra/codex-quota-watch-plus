"""Authenticated task overview. Titles are read locally, never sent to push/widgets."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import time

from .codex_catalog import read_catalog, fallback_project

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
    catalog = read_catalog(home)
    for row in rows:
        identity = row['session'] or row['id']
        if identity in seen:
            continue
        seen.add(identity)
        if catalog.available and identity not in catalog:
            continue  # Removed or foreign tasks must not reappear from old event logs.
        metadata = catalog.get(identity, {})
        if metadata.get('archived'):
            continue
        project, project_id = fallback_project(row['project'])
        age = now - datetime.fromisoformat(row['updated_at']).timestamp()
        stale = row['status'] in ('running', 'needs_approval', 'needs_input', 'stalled') and age > 900
        tasks.append({
            'id': identity, 'project': metadata.get('project', project),
            'project_id': metadata.get('project_id', project_id), 'title': metadata.get('display_title'),
            'status': row['status'], 'phase': row['phase'] or PHASES.get(row['status'], '状态待确认'),
            'updated_at': row['updated_at'], 'started_at': row['started_at'],
            'stale': stale, 'recent': json.loads(row['recent']) if row['recent'] else [],
        })
    # Desktop tasks without observed activity remain distinguishable, but never count as running.
    for identity, metadata in catalog.items():
        if identity in seen or metadata.get('archived'):
            continue
        def timestamp(key):
            value = metadata.get(key)
            try:
                return datetime.fromtimestamp(float(value), timezone.utc).isoformat() if value else ''
            except (ValueError, TypeError, OverflowError, OSError):
                return ''
        tasks.append({
            'id': identity, 'project': metadata['project'], 'project_id': metadata['project_id'],
            'title': metadata['display_title'], 'status': 'untracked', 'phase': '尚未采集到任务活动',
            'updated_at': timestamp('updated_at'), 'started_at': timestamp('created_at'),
            'stale': False, 'recent': [],
        })
    # Match project order from the desktop; preserve latest-activity order within each project.
    tasks.sort(key=lambda t: t['updated_at'], reverse=True)
    tasks.sort(key=lambda t: catalog.get(t['id'], {}).get('project_order', 100000))
    return {'updated_at': datetime.fromtimestamp(now, timezone.utc).isoformat(), 'tasks': tasks}
