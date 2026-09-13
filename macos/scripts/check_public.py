from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
files = [root / n for n in ['main.swift','README.md','UPSTREAM.md','LICENSE','build_app.sh','.gitignore']]
files += list((root/'docs').rglob('*.md')) + list((root/'scripts').glob('*')) + list((root/'.github').rglob('*.yml'))
files += [p for p in (root/'Sources').rglob('*') if p.is_file()]
files += list((root.parent/'shared-widgets').glob('*.swift'))
patterns = [r'/Users/[A-Za-z0-9_-]+/', r'sk-[A-Za-z0-9_-]{20,}', r'Bearer [A-Za-z0-9._-]{20,}', r'192\.168\.\d+\.\d+']
for p in files:
    if not p.is_file(): raise SystemExit('Missing public file: '+str(p))
    text = p.read_text()
    for pattern in patterns:
        if re.search(pattern, text): raise SystemExit('Review sensitive pattern in '+str(p.relative_to(root)))
assert re.fullmatch(r'\d+\.\d+\.\d+\n?', (root.parent/'VERSION').read_text())
print('Public-file checks passed:', len(files), 'files (pattern scan, not a security audit)')
