"""Verify that host and sandboxed widget resolve the same authorized App Group."""
from pathlib import Path
import os, plistlib, re, subprocess, sys
app = Path(sys.argv[1])
groups = []
for bundle in [app, app/'Contents/PlugIns/CodexUsageWidget.appex']:
    info = plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
    group = info['WidgetAppGroup']
    groups.append(group)
    ent = plistlib.loads(subprocess.run(['codesign','-d','--entitlements',':-',str(bundle)],capture_output=True,check=True).stdout)
    assert ent['com.apple.security.application-groups'] == [group], 'Runtime group differs from signed entitlement'
    signing = subprocess.run(['codesign','-dv',str(bundle)],capture_output=True,text=True,check=True).stderr
    team = re.search(r'^TeamIdentifier=([A-Z0-9]{10})$',signing,re.M)
    if team:
        assert group.startswith(team.group(1)+'.'), 'Shared container must be prefixed by signing team'
    else:
        assert os.environ.get('ALLOW_UNSIGNED_WIDGET_BUILD') == '1', 'Unsigned widgets cannot share live data'
assert groups[0] == groups[1], 'Host and widget groups differ'
print('PASS: host and widget share matching signed App Group')
