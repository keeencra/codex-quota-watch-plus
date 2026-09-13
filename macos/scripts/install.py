"""Install the integrated display while retaining existing widget identities and data."""
from pathlib import Path
import datetime,os,plistlib,shutil,signal,subprocess,sys
source=Path(sys.argv[1]).resolve()
subprocess.run(['codesign','--verify','--deep','--strict',str(source)],check=True)
identity='local.codex.usagebar'
def bundle_id(path):
    try:return plistlib.loads((path/'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier')
    except (OSError,ValueError):return None
if bundle_id(source)!=identity:raise SystemExit('Unexpected source bundle identity')
home=Path.home();applications=home/'Applications';applications.mkdir(exist_ok=True)
legacy=applications/'CodexUsageBarTotal.app'
target=legacy if legacy.exists() else applications/'CodeCompanionMac.app'
if target.exists() and bundle_id(target)!=identity:raise SystemExit('Destination belongs to another application')
label='local.codex.usagebar';plist=home/'Library/LaunchAgents'/f'{label}.plist'
if plist.exists():
    old=plistlib.loads(plist.read_bytes())
    allowed=[str(p/'Contents/MacOS/CodexUsageBar') for p in [legacy,applications/'CodeCompanionMac.app']]
    if old.get('ProgramArguments',[None])[0] not in allowed:raise SystemExit('Existing launch service has an unexpected executable; left unchanged')
backup=home/'Library/Application Support/CodeCompanionMac/Backups'/datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup.mkdir(parents=True,mode=0o700)
stage=applications/'.CodeCompanionMac-install'
if stage.exists():raise SystemExit('An unfinished installation already exists; left unchanged')
shutil.copytree(source,stage)
subprocess.run(['xattr','-cr',str(stage)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(stage)],check=True)
subprocess.run(['launchctl','bootout',f'gui/{os.getuid()}/{label}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
for line in subprocess.check_output(['ps','-axo','pid=,comm='],text=True).splitlines():
    parts=line.strip().split(None,1)
    if len(parts)==2 and parts[1]==str(target/'Contents/MacOS/CodexUsageBar'):
        try:os.kill(int(parts[0]),signal.SIGTERM)
        except ProcessLookupError:pass
had_app=target.exists()
had_plist=plist.exists()
if had_plist:shutil.copy2(plist,backup/'launch-agent.plist')
try:
    if had_app:target.rename(backup/'previous-app')
    stage.rename(target)
    plist.parent.mkdir(parents=True,exist_ok=True)
    plist.write_bytes(plistlib.dumps({'Label':label,'ProgramArguments':[str(target/'Contents/MacOS/CodexUsageBar')],'RunAtLoad':True,'KeepAlive':False}))
    subprocess.run(['launchctl','bootstrap',f'gui/{os.getuid()}',str(plist)],check=True)
    # Register the replaced extension, then retire only its old process.
    # RunAtLoad already starts the host; opening it again creates a duplicate.
    extension = target/'Contents/PlugIns/CodexUsageWidget.appex'
    subprocess.run(['pluginkit','-a',str(extension)],check=True)
    for line in subprocess.check_output(['ps','-axo','pid=,comm='],text=True).splitlines():
        parts=line.strip().split(None,1)
        if len(parts)==2 and parts[1]==str(extension/'Contents/MacOS/CodexUsageWidget'):
            try:os.kill(int(parts[0]),signal.SIGTERM)
            except ProcessLookupError:pass
except Exception:
    subprocess.run(['launchctl','bootout',f'gui/{os.getuid()}/{label}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if target.exists():target.rename(backup/'failed-new-app')
    if had_app:(backup/'previous-app').rename(target)
    if had_plist:
        shutil.copy2(backup/'launch-agent.plist',plist)
        subprocess.run(['launchctl','bootstrap',f'gui/{os.getuid()}',str(plist)],check=False)
    elif plist.exists():plist.unlink()
    if had_app and not had_plist:subprocess.run(['open',str(target)],check=False)
    raise
print('Installed CodeCompanion Mac; retained bundle ID, App Group and widget kind. Previous app and launch settings backed up locally.')
