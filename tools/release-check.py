"""Non-secret-printing tracked configuration and documentation checks."""
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
profile = json.loads((root / 'platform/harmony/build-profile.json5').read_text(encoding='utf-8'))
assert profile['app']['signingConfigs'] == [], 'Tracked signing config must be empty'
failures = []
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
for name in paths:
    path = root / name
    if not name or not path.is_file() or path.suffix.lower() not in ('.json5', '.json', '.yml', '.yaml', '.env'):
        continue
    text = path.read_text(encoding='utf-8', errors='replace')
    if re.search(r'"(?:storePassword|keyPassword)"\s*:\s*"[^"\s]+"', text):
        failures.append(name + ': signing password present')
for name in ['README.md', 'submission/README.md']:
    path = root / name
    for target in re.findall(r'\]\(([^)]+)\)', path.read_text(encoding='utf-8')):
        if '://' not in target and not target.startswith('#') and not (path.parent / target.split('#')[0]).exists():
            failures.append(name + ': broken relative link')
assert not failures, '\n'.join(failures)
print('Release checks passed; Harmony HAP and real-device regression remain separate gates.')
