from pathlib import Path
import json,hashlib,argparse
R=Path(__file__).resolve().parents[1]
def verify(require_bits=False):
 records=[];missing=[]
 for P in sorted((R/'fpga').iterdir()):
  if not P.is_dir():continue
  m=json.loads((P/'verification/build_manifest.json').read_text(encoding='utf-8-sig'))
  for n,h in m['source_sha256'].items():
   p=P/n
   if not p.is_file():missing.append(str(p.relative_to(R)));continue
   if hashlib.sha256(p.read_bytes()).hexdigest().upper()!=h.upper():raise ValueError('Changed frozen input: '+str(p.relative_to(R)))
  bit=P/'blackbox.bit'
  if bit.exists():
   if hashlib.sha256(bit.read_bytes()).hexdigest().upper()!=m['bit_sha256'].upper():raise ValueError('bit mismatch: '+P.name)
  elif require_bits:missing.append(str(bit.relative_to(R)))
  records.append(dict(role=P.name,source_files=len(m['source_sha256']),bit_present=bit.exists(),expected_bit=m['bit_sha256']))
 if missing:raise FileNotFoundError('Restore dependencies/build firmware before proceeding:\n'+'\n'.join(missing))
 return records
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--require-bits',action='store_true');a=p.parse_args()
 print(json.dumps(dict(status='PASS_FROZEN_INPUT_HASHES',projects=verify(a.require_bits)),indent=2))
