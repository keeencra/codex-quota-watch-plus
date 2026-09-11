import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from datetime import datetime,timezone,timedelta

script=Path(__file__).resolve().parents[2]/'scripts/renew_signing.py'
spec=importlib.util.spec_from_file_location('renew',script)
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)

def iso(now, hours):
    return datetime.fromtimestamp(now+hours*3600,timezone.utc).isoformat()

class RenewalTests(unittest.TestCase):
    def test_widget_expiry_triggers_phone_install(self):
        now=1000000
        state={'installed':{'phone':iso(now,100),'widget':iso(now,47),'watch':iso(now,100)}}
        self.assertEqual(r.due_groups(state,now),['phone'])

    def test_valid_week_does_not_renew(self):
        now=1000000
        state={'installed':{k:iso(now,150) for k in ['phone','widget','watch']}}
        self.assertEqual(r.due_groups(state,now),[])

    def test_cached_profile_never_counts_as_renewal(self):
        now=1000000
        state={'installed':{k:iso(now,20) for k in ['phone','widget','watch']}}
        self.assertFalse(r.is_renewed(state,state['installed'],['phone','widget'],now))
        profiles={k:iso(now,150) for k in state['installed']}
        self.assertTrue(r.is_renewed(state,profiles,['phone','widget'],now))
        profiles['widget']=state['installed']['widget']
        self.assertFalse(r.is_renewed(state,profiles,['phone','widget'],now))

    def test_install_failure_preserves_actual_installed_expiry(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);now=datetime.now(timezone.utc).timestamp()
            project=root/'Project.xcodeproj';project.mkdir();(project/'project.pbxproj').touch()
            old={k:iso(now,20) for k in ['phone','widget','watch']}
            new={k:iso(now,150) for k in old}
            r.save(root/'renew-signing-state.json',{'installed':old})
            r.save(root/'renew-signing-config.json',{'project':str(project),'derived_data':str(root/'DerivedData'),'apps':{'phone':{'path':'phone.app'},'watch':{'path':'watch.app'}},'devices':{'phone':'phone-device','watch':'watch-device'}})
            def fake_run(command,log,timeout):
                if 'install' in command:
                    if 'phone-device' in command:raise RuntimeError('offline')
                    receipt=Path(command[command.index('--json-output')+1]);r.save(receipt,{'info':{'outcome':'success'}})
            with patch.object(r,'ROOT',root),patch.object(r,'run',fake_run),patch.object(r,'read_profiles',return_value=new):
                result=r.execute()
            state=json.loads((root/'renew-signing-state.json').read_text())
            self.assertEqual(result['status'],'needs_attention')
            self.assertEqual(result['renewed'],['watch'])
            self.assertEqual(state['installed']['phone'],old['phone'])
            self.assertEqual(state['installed']['widget'],old['widget'])
            self.assertEqual(state['installed']['watch'],new['watch'])



    def test_missing_config_returns_sanitized_failure(self):
        import subprocess,sys
        with tempfile.TemporaryDirectory() as folder:
            result=subprocess.run([sys.executable,str(script),'--state-dir',folder,'--check'],capture_output=True,text=True)
            self.assertEqual(result.returncode,2)
            self.assertEqual(json.loads(result.stdout)['status'],'needs_attention')
            self.assertNotIn('Traceback',result.stderr)

    def test_initialization_refuses_to_replace_existing_state(self):
        import subprocess,sys
        with tempfile.TemporaryDirectory() as folder:
            state=Path(folder)/'renew-signing-state.json';state.write_text('{"installed": "keep"}')
            result=subprocess.run([sys.executable,str(script),'--state-dir',folder,'--record-installed-from',folder],capture_output=True,text=True)
            self.assertEqual(result.returncode,2)
            self.assertEqual(state.read_text(),'{"installed": "keep"}')
