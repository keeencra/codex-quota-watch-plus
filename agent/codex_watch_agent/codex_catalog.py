"""Read-only desktop names and project membership; never return workspace paths."""
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3


def label(value, limit=160):
    return ''.join(c for c in value if c.isprintable()).strip()[:limit] if isinstance(value, str) else ''


def _path(value):
    return str(Path(value.replace('\\', '/')).expanduser()).rstrip('/') if isinstance(value, str) and value else ''


class DesktopCatalog(dict):
    available = False


def read_catalog(home):
    try:
        state = json.loads((home / '.codex-global-state.json').read_text())
        if not isinstance(state, dict):
            state = {}
    except (OSError, ValueError):
        state = {}
    projects, aliases, threads = {}, {}, DesktopCatalog()
    try:
        with closing(sqlite3.connect((home / 'state_5.sqlite').as_uri() + '?mode=ro', uri=True, timeout=1)) as db:
            db.row_factory = sqlite3.Row
            columns = {r['name'] for r in db.execute('PRAGMA table_info(threads)')}
            fields = [c for c in ('id', 'name', 'title', 'cwd', 'project_id', 'archived', 'created_at', 'updated_at') if c in columns]
            if 'id' in fields:
                threads.update({r['id']: dict(r) for r in db.execute('SELECT ' + ','.join(fields) + ' FROM threads')})
                threads.available = True
            try:
                for row in db.execute('SELECT id,name,position FROM projects ORDER BY position'):
                    projects[row['id']] = {'id': row['id'], 'name': label(row['name'], 80) or '未命名项目', 'roots': []}
                for row in db.execute('SELECT project_id,path FROM project_roots ORDER BY position'):
                    if row['project_id'] in projects:
                        projects[row['project_id']]['roots'].append(_path(row['path']))
            except sqlite3.Error:
                pass
    except (sqlite3.Error, ValueError):
        pass
    migrations = state.get('app-server-project-id-by-legacy-project-id-by-host', {})
    if isinstance(migrations, dict):
        # The reader only maps projects from this Codex home, never other hosts.
        migration = migrations.get('local:' + str(home), {})
        if isinstance(migration, dict):
            aliases = {k: v for k, v in migration.items() if isinstance(k, str) and isinstance(v, str)}
    legacy = state.get('local-projects', {})
    if isinstance(legacy, dict):
        for key, value in legacy.items():
            if not isinstance(value, dict):
                continue
            identity = aliases.get(key, key)
            roots = value.get('rootPaths', [])
            projects[identity] = {'id': identity, 'name': label(value.get('name'), 80) or '未命名项目',
                                  'roots': [_path(p) for p in roots if isinstance(p, str)] if isinstance(roots, list) else []}
    order = []
    for key in ('pinned-project-ids', 'project-order'):
        values = state.get(key, [])
        if isinstance(values, list):
            order.extend(aliases.get(v, v) for v in values if isinstance(v, str))
    order = list(dict.fromkeys(order + list(projects)))
    assignments = state.get('thread-project-assignments', {})
    assignments = assignments if isinstance(assignments, dict) else {}
    projectless = state.get('projectless-thread-ids', [])
    projectless = set(v for v in projectless if isinstance(v, str)) if isinstance(projectless, list) else set()
    for identity, thread in threads.items():
        thread['display_title'] = label(thread.get('name')) or label(thread.get('title')) or None
        assignment = assignments.get(identity)
        project_id = thread.get('project_id')
        # Older desktops store explicit project assignments in global state.
        if not project_id and isinstance(assignment, dict) and assignment.get('projectKind') == 'local':
            project_id = assignment.get('projectId')
        project_id = aliases.get(project_id, project_id) if isinstance(project_id, str) else None
        explicit_none = identity in projectless and not project_id
        if project_id not in projects and not explicit_none:
            cwd = _path(thread.get('cwd'))
            matches = [(len(root), pid) for pid, p in projects.items() for root in p['roots']
                       if root and cwd and (cwd == root or cwd.startswith(root + '/'))]
            project_id = max(matches)[1] if matches else None
        project = projects.get(project_id)
        thread['project'] = project['name'] if project else '未分组'
        thread['project_id'] = project['id'] if project else 'ungrouped'
        thread['project_order'] = order.index(project['id']) if project else len(order)
    return threads


def fallback_project(name):
    name = label(name, 80) or '其他任务'
    return name, 'legacy-' + hashlib.sha256(name.encode()).hexdigest()[:16]
