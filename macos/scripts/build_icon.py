"""Package the existing CodeCompanion master artwork as a macOS icon."""
from pathlib import Path
import subprocess,sys,tempfile
root=Path(__file__).resolve().parents[2]
source=root/'docs/assets/brand/codecompanion-master-v3.0.0.png'
with tempfile.TemporaryDirectory() as tmp:
    iconset=Path(tmp)/'AppIcon.iconset';iconset.mkdir()
    for size in [16,32,128,256,512]:
        for scale in [1,2]:
            name=f'icon_{size}x{size}'+('@2x' if scale==2 else '')+'.png'
            subprocess.run(['sips','-z',str(size*scale),str(size*scale),str(source),'--out',str(iconset/name)],check=True,stdout=subprocess.DEVNULL)
    subprocess.run(['iconutil','-c','icns',str(iconset),'-o',sys.argv[1]],check=True)
