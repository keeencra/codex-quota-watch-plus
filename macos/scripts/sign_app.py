"""Sign the host and widget with a matching macOS team-scoped App Group."""
from pathlib import Path
import os, plistlib, re, subprocess, sys
app = Path(sys.argv[1])
root = Path(__file__).resolve().parents[1]
widget = app/'Contents/PlugIns/CodexUsageWidget.appex'
identity = os.environ.get('SIGNING_IDENTITY')
if not identity:
    identities = subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
    match = re.search(r'([0-9A-F]{40}) "(?:Apple Development|Developer ID Application):', identities)
    identity = match.group(1) if match else '-'
# Read the team from the actual signing certificate, never a hard-coded account ID.
subprocess.run(['codesign','--force','--sign',identity,str(app/'Contents/MacOS/CodexUsageBar')],check=True,stderr=subprocess.DEVNULL)
info = subprocess.run(['codesign','-dv',str(app/'Contents/MacOS/CodexUsageBar')],capture_output=True,text=True,check=True).stderr
match = re.search(r'^TeamIdentifier=([A-Z0-9]{10})$',info,re.M)
team = match.group(1) if match else None
if not team and os.environ.get('ALLOW_UNSIGNED_WIDGET_BUILD') != '1':
    raise SystemExit('Widget data sharing requires an Apple signing identity. Set SIGNING_IDENTITY, or use ALLOW_UNSIGNED_WIDGET_BUILD=1 for compile-only CI (no working widget data sharing).')
group = team+'.local.codex.usagebar' if team else 'group.local.codex.usagebar'
for bundle, template in [(widget,'Widget/Widget.entitlements'),(app,'Shared/Host.entitlements')]:
    plist_path = bundle/'Contents/Info.plist'
    plist = plistlib.loads(plist_path.read_bytes()); plist['WidgetAppGroup']=group
    plist_path.write_bytes(plistlib.dumps(plist))
    entitlements = plistlib.loads((root/'Sources'/template).read_bytes())
    entitlements['com.apple.security.application-groups']=[group]
    ent_path = app.parent/(bundle.stem+'.entitlements')
    ent_path.write_bytes(plistlib.dumps(entitlements))
    subprocess.run(['codesign','--force','--sign',identity,'--entitlements',str(ent_path),str(bundle)],check=True,stderr=subprocess.DEVNULL)
print('Signed host and widget with matching team App Group' if team else 'Compile-only unsigned widget build; data sharing unavailable')
