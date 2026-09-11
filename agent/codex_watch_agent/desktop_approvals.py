"""Version-gated local desktop IPC adapter for live native command approvals.

Uses the desktop's existing follower decision route; never clicks UI, edits
permissions or dispatches a command. The Unix socket must belong to this user.
Only command approvals with a complete command are supported by this adapter.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import selectors
import socket
import sqlite3
import stat
import struct
import threading
import time
import uuid

from .approvals import ApprovalStore
from .task_events import state_dir

STREAM_VERSION = 11
DECISION_METHOD = 'thread-follower-command-approval-decision'


class DesktopApprovals:
    def __init__(self, root=None, codex_home=None):
        self.root = root or state_dir()
        self.home = Path(codex_home or os.environ.get('CODEX_HOME', Path.home()/'.codex')).expanduser()
        self.store = ApprovalStore(self.root)
        self.socket = None
        self.buffer = bytearray()
        self.client_id = None
        self.states = {}
        self.subscribed = set()
        self.requests = {}
        self.outgoing = {}
        self.owner_by_thread = {}
        self.last_discovery = 0

    @staticmethod
    def check_socket(path):
        owner = os.getuid()
        info, parent = path.lstat(), path.parent.lstat()
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != owner or parent.st_uid != owner or parent.st_mode & 0o022:
            raise OSError('Untrusted local IPC socket')

    def send(self, value):
        raw = json.dumps(value, ensure_ascii=False).encode()
        self.socket.sendall(struct.pack('<I', len(raw)) + raw)

    def broadcast_follow(self, thread, following=True):
        self.send({'type':'broadcast','method':'thread-stream-following-changed','version':1,
                   'sourceClientId':self.client_id,'params':{'conversationId':thread,'hostId':'local','following':following}})

    def discover(self):
        path = self.home/'state_5.sqlite'
        if not path.exists():
            return
        with sqlite3.connect(f'file:{path}?mode=ro',uri=True,timeout=1) as db:
            ids = {r[0] for r in db.execute('SELECT id FROM threads WHERE archived=0 ORDER BY updated_at DESC LIMIT 60')}
        for thread in ids-self.subscribed:
            self.broadcast_follow(thread)
        for thread in self.subscribed-ids:
            if not any(v['thread']==thread for v in self.requests.values()):
                self.broadcast_follow(thread,False)
                self.states.pop(thread,None)
        self.subscribed = ids

    @staticmethod
    def apply_patch(state, patch):
        path = patch.get('path',[])
        if not isinstance(path,list) or not path:
            raise ValueError('Snapshot required')
        if path[0] not in ('requests','cwd','sessionId','parentThreadId'):
            return
        target = state
        for key in path[:-1]:
            target = target[key]
        key = path[-1]
        op = patch.get('op')
        if op == 'remove':
            if isinstance(target,list):target.pop(key)
            else:target.pop(key,None)
        elif op in ('add','replace'):
            if isinstance(target,list) and op=='add':target.insert(key,patch['value'])
            else:target[key]=patch['value']
        else:
            raise ValueError('Unsupported patch')

    def receive(self, message):
        if message.get('type')=='client-discovery-request':
            self.send({'type':'client-discovery-response','requestId':message['requestId'],'response':{'canHandle':False}})
            return
        if message.get('type')=='response':
            if message.get('method')=='initialize' and message.get('resultType')=='success':
                self.client_id=message['result']['clientId']
                return
            key=self.outgoing.pop(message.get('requestId'),None)
            if key:
                item=self.requests.get(key)
                if item:
                    if message.get('resultType')=='success' and message.get('handledByClientId')==item['owner'] and message.get('result',{}).get('ok') is True:
                        self.store.acknowledge(item['local'])
                    else:self.store.close(item['local'])
                    item['forwarded']=True
            return
        if message.get('type')!='broadcast' or message.get('method')!='thread-stream-state-changed':
            return
        params=message.get('params',{})
        if params.get('hostId')!='local':return
        thread=params.get('conversationId');change=params.get('change',{})
        if thread not in self.subscribed:return
        if message.get('version')!=STREAM_VERSION:
            self.invalidate_thread(thread);return
        owner=message.get('sourceClientId')
        if change.get('type')=='snapshot':
            full=change.get('conversationState',{})
            if full.get('id')!=thread or full.get('parentThreadId'):
                self.invalidate_thread(thread);return
            state={k:full.get(k) for k in ('requests','cwd','sessionId','parentThreadId')}
            state['revision']=change.get('revision');self.states[thread]=state
            self.owner_by_thread[thread]=owner
        elif change.get('type')=='patches':
            state=self.states.get(thread)
            if state is None or state['revision']!=change.get('baseRevision') or self.owner_by_thread.get(thread)!=owner:
                self.invalidate_thread(thread)
                self.broadcast_follow(thread,False);self.broadcast_follow(thread,True)
                return
            try:
                for patch in change.get('patches',[]):self.apply_patch(state,patch)
                state['revision']=change.get('revision')
            except (ValueError,KeyError,IndexError,TypeError):
                self.invalidate_thread(thread);return
        else:return
        self.reconcile(thread,owner)

    def invalidate_thread(self,thread):
        self.states.pop(thread,None)
        for item in self.requests.values():
            if item['thread']==thread and not item.get('forwarded'):
                self.store.close(item['local']);item['forwarded']=True

    def reconcile(self,thread,owner):
        state=self.states.get(thread,{})
        live=set()
        for request in state.get('requests') or []:
            if not isinstance(request,dict) or request.get('method')!='item/commandExecution/requestApproval':continue
            params=request.get('params',{})
            if params.get('threadId')!=thread or not params.get('turnId') or not isinstance(params.get('command'),str) or not params['command']:
                continue
            allowed=params.get('availableDecisions')
            if isinstance(allowed,list) and 'accept' not in allowed:continue
            native_id=request.get('id')
            if not isinstance(native_id,(str,int)) or isinstance(native_id,bool):continue
            key=(thread,json.dumps(native_id))
            live.add(key)
            fingerprint=hashlib.sha256(json.dumps(params,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
            if key in self.requests:
                item=self.requests[key]
                if fingerprint!=item['native_fingerprint'] or owner!=item['owner']:
                    self.store.close(item['local']);item['forwarded']=True
                continue
            if not self.store.enabled():continue
            event={'hook_event_name':'PermissionRequest','session_id':str(state.get('sessionId') or thread),
                   'turn_id':params['turnId'],'cwd':params.get('cwd') or state.get('cwd') or 'Codex',
                   'tool_name':'Codex 命令审批','tool_input':params}
            try:row=self.store.create(event)
            except (ValueError,OSError):continue
            self.requests[key]={'local':row['id'],'thread':thread,'native_id':native_id,'owner':owner,
                                'native_fingerprint':fingerprint,'forwarded':False,'sending':False}
            # Same session/turn and request id feed the durable notification queue.
            from .task_events import TaskEventStore
            event['request_id']=str(native_id)
            TaskEventStore(self.root).record(event)
        for key,item in self.requests.items():
            if item['thread']==thread and key not in live and not item.get('forwarded') and not item.get('sending'):
                self.store.close(item['local']);item['forwarded']=True

    def tick(self):
        for key,item in list(self.requests.items()):
            if item['forwarded']:continue
            if not self.store.enabled():
                self.store.close(item['local']);item['forwarded']=True;continue
            decision=self.store.tick(item['local'],consume=False)
            if decision=='closed':item['forwarded']=True;continue
            if item['sending']:continue
            if decision not in ('allow','deny'):continue
            # Validate the still-live request, owner, and complete parameters again.
            state=self.states.get(item['thread'])
            request=next((r for r in (state or {}).get('requests',[]) if r.get('id')==item['native_id']),None)
            digest=hashlib.sha256(json.dumps(request.get('params'),sort_keys=True,ensure_ascii=False).encode()).hexdigest() if request else None
            if digest!=item['native_fingerprint'] or self.owner_by_thread.get(item['thread'])!=item['owner']:
                self.store.close(item['local']);item['forwarded']=True;continue
            request_id=str(uuid.uuid4());self.outgoing[request_id]=key;item['sending']=True
            self.send({'type':'request','requestId':request_id,'sourceClientId':self.client_id,
                       'targetClientId':item['owner'],'method':DECISION_METHOD,'version':1,'timeoutMs':5000,
                       'params':{'conversationId':item['thread'],'requestId':item['native_id'],
                                 'decision':'accept' if decision=='allow' else 'decline'}})

    def serve(self):
        path=self.home/'ipc/ipc.sock';self.check_socket(path)
        self.socket=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        self.socket.settimeout(2);self.socket.connect(str(path));self.socket.settimeout(.5)
        self.send({'type':'request','requestId':'quota-init','method':'initialize','params':{'clientType':'codex-quota-watch'}})
        try:
            while True:
                try:
                    data=self.socket.recv(65536)
                    if not data:raise OSError('Desktop disconnected')
                    self.buffer.extend(data)
                    while len(self.buffer)>=4:
                        length=struct.unpack('<I',self.buffer[:4])[0]
                        if not 0<length<=32*1024*1024:raise OSError('Unsupported desktop frame')
                        if len(self.buffer)<length+4:break
                        message=json.loads(self.buffer[4:length+4]);del self.buffer[:length+4]
                        self.receive(message)
                except socket.timeout:pass
                if self.client_id and time.monotonic()-self.last_discovery>5:
                    self.discover();self.last_discovery=time.monotonic()
                self.tick()
        finally:
            self.socket.close()
            for item in self.requests.values():
                if not item.get('forwarded'):self.store.close(item['local'])


def run_desktop_bridge():
    while True:
        try:DesktopApprovals().serve()
        except Exception:
            # No raw IPC, commands, titles, tokens or local paths in logs.
            time.sleep(5)


def start_desktop_bridge():
    thread=threading.Thread(target=run_desktop_bridge,name='desktop-approvals',daemon=True)
    thread.start()
    return thread
