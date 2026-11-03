from pathlib import Path
import argparse,json,hashlib
R=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description='Import already-authorized bit files by exact frozen SHA256;no device access')
p.add_argument('directory',type=Path);a=p.parse_args()
versions=json.loads((R/'verification/versions.json').read_text(encoding='utf8'))
available={hashlib.sha256(f.read_bytes()).hexdigest().upper():f for f in a.directory.rglob('*.bit')}
for role,m in versions.items():
 if m['bit_sha256'].upper() not in available:raise FileNotFoundError('Missing matching firmware: '+role)
 target=R/m['project_relative']/'blackbox.bit';data=available[m['bit_sha256'].upper()].read_bytes()
 if target.exists() and target.read_bytes()!=data:raise FileExistsError('Preserving existing changed bit: '+str(target))
 target.write_bytes(data)
print('PASS imported four matching firmwares;no hardware access')
