from pathlib import Path
import subprocess,os,json,time
import argparse
parser=argparse.ArgumentParser();parser.add_argument('--iphone',required=True);parser.add_argument('--watch',required=True);args=parser.parse_args()
r=Path.cwd();out=r/'docs/assets/gallery/v3.0.0';out.mkdir(exist_ok=True)
products=Path('/tmp/CodeCompanionV3GalleryBuild/Build/Products')
devices={'iphone':(args.iphone,'com.example.CodexQuota',products/'Debug-iphonesimulator/CodingQuota.app'),'watch':(args.watch,'com.example.CodexQuota.watchkitapp',products/'Debug-watchsimulator/CodingQuota Watch App.app')}
manifest=[]
for platform,(device,bundle,app) in devices.items():
 subprocess.run(['xcrun','simctl','install',device,str(app)],check=True,stdout=subprocess.DEVNULL)
 subprocess.run(['xcrun','simctl','status_bar',device,'override','--time','9:41','--batteryState','charged','--batteryLevel','100'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 scenarios=[]
 for screen in ['home','quota']:
  for plan in ['pro','plus']:scenarios.append((screen,plan,'ok'))
 if platform=='iphone':
  for plan in ['pro','plus']:scenarios.append(('home',plan,'not_configured'))
 for screen in ['tasks','task','tasks-empty','approvals','approvals-empty','approval']:scenarios.append((screen,'pro','ok'))
 for status in ['ok','not_configured','error']:scenarios.append(('balance','pro',status))
 if platform=='iphone':
  for screen in ['settings','notifications','diagnostics','about']:scenarios.append((screen,'pro','ok'))
  for plan in ['pro','plus']:
   for status in ['ok','not_configured']:scenarios.append(('widgets',plan,status))
 else:scenarios.append(('today','pro','ok'))
 for screen,plan,status in scenarios:
  subprocess.run(['xcrun','simctl','terminate',device,bundle],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  env=os.environ.copy();env.update(SIMCTL_CHILD_GALLERY_SCREEN=screen,SIMCTL_CHILD_GALLERY_PLAN=plan,SIMCTL_CHILD_GALLERY_BALANCE=status)
  subprocess.run(['xcrun','simctl','launch',device,bundle],env=env,check=True,stdout=subprocess.DEVNULL)
  time.sleep(1.2)
  name=f'{platform}-{screen}-{plan}-{status}'
  png=Path('/tmp')/(name+'.png');jpg=out/(name+'.jpg')
  subprocess.run(['xcrun','simctl','io',device,'screenshot',str(png)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True)
  subprocess.run(['sips','-s','format','jpeg','-s','formatOptions','75',str(png),'--out',str(jpg)],stdout=subprocess.DEVNULL,check=True)
  manifest.append(dict(file=jpg.name,platform=platform,screen=screen,plan=plan,deepseek=status));print(name,flush=True)
(r/'docs/gallery/manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
