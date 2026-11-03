"""Repository paths plus explicitly registered local builds;no device actions."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
FILES={'player':'verification/player.json','tf-maintenance':'verification/network.json'}
def pointer(role):
 if role in FILES:m=json.loads((ROOT/FILES[role]).read_text(encoding='utf8'))
 else:
  v=json.loads((ROOT/'verification/versions.json').read_text(encoding='utf8'))[role]
  m=dict(v,runtime_tag='ART9' if role=='fallback-art9' else 'UART',uart_controls=True,diagnostic_only=False)
 local=ROOT/'runtime/local-firmware.json'
 if local.exists():m=json.loads(local.read_text(encoding='utf8')).get(role,m)
 p=(ROOT/m['project_relative']).resolve()
 if not any(p.is_relative_to((ROOT/x).resolve()) for x in ('fpga','runtime/firmware')):raise ValueError('Firmware path outside allowed repository directories')
 return m
def relative(role):return pointer(role)['project_relative']
