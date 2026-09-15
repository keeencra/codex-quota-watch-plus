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

    def __init__(self):
        super().__init__()
        self.projects = []
        self.sections = []


def read_catalog(home):
    try:
        state = json.loads((home / '.codex-global-state.json').read_text())
        if not isinstance(state, dict):
            state = {}
    except (OSError, ValueError):
        state = {}
    projects, aliases, threads = {}, {}, DesktopCatalog()
    database_order = []
    try:
        with closing(sqlite3.connect((home / 'state_5.sqlite').as_uri() + '?mode=ro', uri=True, timeout=1)) as db:
            db.row_factory = sqlite3.Row
            columns = {r['name'] for r in db.execute('PRAGMA table_info(threads)')}
            fields = [c for c in ('id', 'name', 'title', 'cwd', 'project_id', 'archived', 'created_at', 'updated_at', 'thread_section_id', 'section_position', 'is_pinned') if c in columns]
            if 'id' in fields:
                threads.update({r['id']: dict(r) for r in db.execute('SELECT ' + ','.join(fields) + ' FROM threads')})
                threads.available = True
            try:
                for row in db.execute('SELECT id,name,position FROM projects ORDER BY position'):
                    database_order.append(row['id'])
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
    migration_status = state.get('app-server-projects-migration-by-host', {})
    host_status = migration_status.get('local:' + str(home), {}) if isinstance(migration_status, dict) else {}
    # Once desktop projects migrate, SQLite positions/names are authoritative.
    # The legacy JSON may remain on disk after dragging or renaming a project.
    migrated = isinstance(host_status, dict) and host_status.get('projectsMigrated') is True and bool(database_order)
    legacy = state.get('local-projects', {})
    if isinstance(legacy, dict):
        for key, value in legacy.items():
            if not isinstance(value, dict):
                continue
            identity = aliases.get(key, key)
            if migrated:
                continue
            roots = value.get('rootPaths', [])
            projects[identity] = {'id': identity, 'name': label(value.get('name'), 80) or '未命名项目',
                                  'roots': [_path(p) for p in roots if isinstance(p, str)] if isinstance(roots, list) else []}
    order = []
    for key in ('pinned-project-ids', 'project-order'):
        values = state.get(key, [])
        if isinstance(values, list):
            order.extend(aliases.get(v, v) for v in values if isinstance(v, str))
    if migrated:
        # Pinning is still stored in global state; ordinary order is now in SQLite.
        pinned = state.get('pinned-project-ids', [])
        pinned = [aliases.get(v, v) for v in pinned if isinstance(v, str)] if isinstance(pinned, list) else []
        order = pinned + database_order
    order = list(dict.fromkeys(pid for pid in order + list(projects) if pid in projects))
    threads.projects = [{'id': pid, 'name': projects[pid]['name']} for pid in order]
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
    _read_sections(home, state, aliases, threads)
    return threads


def fallback_project(name):
    name = label(name, 80) or '其他任务'
    return name, 'legacy-' + hashlib.sha256(name.encode()).hexdigest()[:16]


def _read_sections(home, state, aliases, catalog):
    """Translate the current account's unified sidebar, without exposing host paths."""
    atoms = state.get('electron-persisted-atom-state', {})
    if not isinstance(atoms, dict):
        return
    accounts = atoms.get('sidebar-custom-sections-v3', {})
    if not isinstance(accounts, dict):
        return
    try:
        account = json.loads((home / 'auth.json').read_text()).get('tokens', {}).get('account_id')
    except (OSError, ValueError, AttributeError):
        account = None
    config = accounts.get(account) if account else next(iter(accounts.values()), None) if len(accounts) == 1 else None
    if not isinstance(config, dict) or not isinstance(config.get('sections'), list):
        return
    projects = {p['id']: p for p in catalog.projects}
    specs = {'pinned': {'id': 'pinned', 'name': '置顶', 'items': []},
             'threads': {'id': 'threads', 'name': '项目', 'items': []},
             'chats': {'id': 'chats', 'name': '任务', 'items': []}}
    custom, host_sections = [], {}
    for section in config['sections']:
        if not isinstance(section, dict) or not label(section.get('id')):
            continue
        sid = section['id']
        if sid in specs:
            continue
        custom.append(sid)
        specs[sid] = {'id': sid, 'name': label(section.get('name'), 80) or '未命名分区', 'items': []}
        hosts = section.get('hostSectionIds', {})
        if isinstance(hosts, dict) and isinstance(hosts.get('local'), str):
            host_sections[hosts['local']] = sid
    order = config.get('sectionOrder', [])
    order = order if isinstance(order, list) else []
    order = [v.removeprefix('custom:') for v in order if isinstance(v, str)]
    order = list(dict.fromkeys(v for v in ['pinned'] + order + custom + ['threads', 'chats'] if v in specs))
    used_projects, used_tasks = set(), set()

    def add(sid, kind, identity):
        if kind == 'project':
            identity = aliases.get(identity, identity)
            if identity not in projects or identity in used_projects:
                return
            used_projects.add(identity)
        else:
            if identity not in catalog or catalog[identity].get('archived') or identity in used_tasks:
                return
            used_tasks.add(identity)
        specs[sid]['items'].append({'kind': kind, 'id': identity})

    # Explicit pinning wins over stale section entries.
    pinned = state.get('pinned-project-ids', [])
    for pid in pinned if isinstance(pinned, list) else []:
        if isinstance(pid, str):
            add('pinned', 'project', pid)
    for tid, task in catalog.items():
        if task.get('is_pinned'):
            add('pinned', 'task', tid)
    for section in config['sections']:
        if not isinstance(section, dict) or section.get('id') not in custom:
            continue
        keys = section.get('itemKeys', [])
        for key in keys if isinstance(keys, list) else []:
            if not isinstance(key, str):
                continue
            if key.startswith('codex:project:'):
                add(section['id'], 'project', key[len('codex:project:'):])
            elif key.startswith('codex:thread:local:'):
                add(section['id'], 'task', key[len('codex:thread:local:'):])
    # Newly moved local tasks can arrive in SQLite before the UI item list.
    for tid, task in sorted(catalog.items(), key=lambda pair: pair[1].get('section_position') or 0):
        if task.get('thread_section_id') in host_sections:
            add(host_sections[task['thread_section_id']], 'task', tid)
    for pid in projects:
        add('threads', 'project', pid)
    for tid, task in catalog.items():
        if task['project_id'] not in projects:
            add('chats', 'task', tid)
    catalog.sections = [specs[sid] for sid in order if specs[sid]['items'] or sid in custom]
    rank = {}
    for section in catalog.sections:
        for item in section['items']:
            rank[(item['kind'], item['id'])] = len(rank)
    catalog.projects.sort(key=lambda p: rank.get(('project', p['id']), len(rank)))
    for tid, task in catalog.items():
        task['project_order'] = rank.get(('task', tid), rank.get(('project', task['project_id']), len(rank)))
