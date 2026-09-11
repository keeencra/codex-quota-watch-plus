import copy
import json
import time
import pytest
from codex_watch_agent.desktop_approvals import DesktopApprovals, STREAM_VERSION, DECISION_METHOD


@pytest.fixture
def bridge(tmp_path):
    (tmp_path/'remote-approval.json').write_text('{"enabled":true}')
    b=DesktopApprovals(tmp_path,tmp_path/'codex');b.subscribed.add('thread');b.client_id='watch-client'
    b.sent=[];b.send=b.sent.append
    return b


def snapshot(requests=None,version=STREAM_VERSION,revision=1):
    request={'id':'native-request','method':'item/commandExecution/requestApproval','params':{
        'threadId':'thread','turnId':'turn','command':'/usr/bin/true','cwd':'/private/project',
        'availableDecisions':['accept','cancel']}}
    return {'type':'broadcast','method':'thread-stream-state-changed','version':version,'sourceClientId':'owner',
            'params':{'hostId':'local','conversationId':'thread','change':{'type':'snapshot','revision':revision,
            'conversationState':{'id':'thread','requests':[request] if requests is None else requests,'cwd':'/private/project','sessionId':'session','parentThreadId':None,'turns':['PRIVATE-REPLY']}}}}


def test_native_request_uses_exact_owner_and_one_shot_decision_and_waits_for_receipt(bridge):
    bridge.receive(snapshot());row=bridge.store.pending()[0]
    assert 'PRIVATE-REPLY' not in json.dumps(bridge.states)
    bridge.store.decide(row['id'],row['nonce'],row['fingerprint'],'allow')
    bridge.tick();bridge.tick()
    assert len(bridge.sent)==1
    message=bridge.sent[0]
    assert message['method']==DECISION_METHOD and message['version']==1
    assert message['targetClientId']=='owner'
    assert message['params']=={'conversationId':'thread','requestId':'native-request','decision':'accept'}
    assert bridge.store.get(row['id'])['status']=='submitted'
    bridge.receive({'type':'response','requestId':message['requestId'],'resultType':'success','handledByClientId':'owner','result':{'ok':True}})
    assert bridge.store.get(row['id'])['status']=='consumed'
    assert bridge.store.get(row['id'])['details']==''


def test_other_owner_receipt_cannot_confirm(bridge):
    bridge.receive(snapshot());row=bridge.store.pending()[0]
    bridge.store.decide(row['id'],row['nonce'],row['fingerprint'],'allow');bridge.tick()
    bridge.receive({'type':'response','requestId':bridge.sent[0]['requestId'],'resultType':'success','handledByClientId':'wrong','result':{'ok':True}})
    assert bridge.store.get(row['id'])['status']=='expired'


def test_native_request_resolution_or_command_change_invalidates_review(bridge):
    bridge.receive(snapshot());row=bridge.store.pending()[0]
    changed=snapshot();changed['params']['change']['conversationState']['requests'][0]['params']['command']='other command'
    bridge.receive(changed)
    assert bridge.store.get(row['id'])['status']=='expired'
    bridge.tick();assert not bridge.sent


def test_unsupported_protocol_is_fail_closed(bridge):
    bridge.receive(snapshot(version=999));assert bridge.store.pending()==[]
    bridge.receive(snapshot());row=bridge.store.pending()[0]
    bridge.receive(snapshot(version=999));assert bridge.store.get(row['id'])['status']=='expired'


def test_patches_remove_live_request_without_replaying_chat(bridge):
    bridge.receive(snapshot());row=bridge.store.pending()[0]
    update={'type':'broadcast','method':'thread-stream-state-changed','version':STREAM_VERSION,'sourceClientId':'owner',
            'params':{'hostId':'local','conversationId':'thread','change':{'type':'patches','baseRevision':1,'revision':2,
            'patches':[{'op':'remove','path':['requests',0]},{'op':'add','path':['turns',0],'value':'PRIVATE'}]}}}
    bridge.receive(update);assert bridge.store.get(row['id'])['status']=='expired'
    assert 'PRIVATE' not in json.dumps(bridge.states)


def test_native_file_or_missing_command_not_blindly_approvable(bridge):
    message=snapshot();r=message['params']['change']['conversationState']['requests'][0]
    r['method']='item/fileChange/requestApproval';bridge.receive(message)
    assert bridge.store.pending()==[]
    r['method']='item/commandExecution/requestApproval';del r['params']['command'];bridge.receive(message)
    assert bridge.store.pending()==[]


def test_unknown_patch_shape_requires_new_snapshot(bridge):
    bridge.receive(snapshot());row=bridge.store.pending()[0]
    update={'type':'broadcast','method':'thread-stream-state-changed','version':STREAM_VERSION,'sourceClientId':'owner',
            'params':{'hostId':'local','conversationId':'thread','change':{'type':'patches','baseRevision':1,'revision':2,
            'patches':[{'op':'replace','path':[],'value':{}}]}}}
    bridge.receive(update)
    assert bridge.store.get(row['id'])['status']=='expired'
    bridge.tick();assert not bridge.sent
