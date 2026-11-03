"""Restore locally licensed official HDL and Windows glyphs;no hardware I/O.

Only files listed by the lock are written,and every output must match its
frozen source hash.Existing mismatched files are never overwritten.
"""
from pathlib import Path
import argparse,json,hashlib,zipfile,os
R=Path(__file__).resolve().parents[1]
sha=lambda b:hashlib.sha256(b).hexdigest().upper()
def target(name):
 p=(R/name).resolve()
 if not p.is_relative_to(R.resolve()):raise ValueError('Path outside repository')
 return p
def put(name,data,expected):
 assert sha(data)==expected.upper(),'Restored content does not match frozen hash: '+name
 p=target(name)
 if p.exists():
  if p.read_bytes()!=data:raise FileExistsError('Existing modified input is preserved: '+name)
 else:p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--official-root',type=Path,help='Authorized HX4S20_Contest_202606 directory')
 parser.add_argument('--fonts-dir',type=Path,default=Path(os.environ.get('WINDIR','C:/Windows'))/'Fonts')
 parser.add_argument('--fonts-only',action='store_true')
 args=parser.parse_args();count=0
 if not args.fonts_only:
  if not args.official_root:parser.error('--official-root is required unless --fonts-only')
  official=args.official_root.resolve()
  for entry in json.loads((R/'dependencies/official-inputs.json').read_text(encoding='utf8'))['files']:
   src=entry['source'];p=(official/src['path']).resolve()
   if not p.is_relative_to(official):raise ValueError('Official source path outside selected root')
   # Some official downloads have one fewer wrapper folder.Find only an exact
   # matching local input;never substitute a similarly named different file.
   base_hash=src.get('archive_sha256') if src['kind']=='zip' else src.get('sha256')
   if not p.is_file() or (base_hash and sha(p.read_bytes())!=base_hash):
    candidates=[f for f in official.rglob(p.name) if f.is_file() and f.resolve().is_relative_to(official) and (not base_hash or sha(f.read_bytes())==base_hash)]
    if not candidates:raise FileNotFoundError('No matching licensed input under selected root: '+src['path'])
    p=candidates[0]
   if src['kind']=='zip':
    if src.get('archive_sha256') and sha(p.read_bytes())!=src['archive_sha256']:raise ValueError('Official archive version/hash differs: '+p.name)
    with zipfile.ZipFile(p) as z:data=z.read(src['member'])
   else:
    data=p.read_bytes()
    if src.get('sha256') and sha(data)!=src['sha256']:raise ValueError('Official source hash differs: '+src['path'])
   if 'adaptation' in entry:
    data=b''.join(data[o['copy'][0]:o['copy'][1]] if 'copy' in o else o['insert'].encode('utf8') for o in entry['adaptation'])
   put(entry['target'],data,entry['sha256']);count+=1
 from PIL import Image,ImageFont,ImageDraw
 for entry in json.loads((R/'dependencies/font-inputs.json').read_text(encoding='utf8'))['files']:
  masks={}
  for s in entry['labels']:
   font=ImageFont.truetype(str(args.fonts_dir/s['font']),s['size']);im=Image.new('1',(64,16));ImageDraw.Draw(im).text((s['x'],s['y']),s['text'],font=font,fill=1)
   masks[s['id']]={y*64+x for y in range(16) for x in range(64) if im.getpixel((x,y))}
  text=target(entry['template']).read_text(encoding='utf8')
  if entry['kind']=='memory':
   for s in entry['labels']:
    block=''.join(f"  label_memory[{s['id']*1024+i}]=1'b1;\n" for i in sorted(masks[s['id']]))
    token=f"@@LOCAL_FONT_ROWS_ID_{s['id']}@@\n";assert text.count(token)==1;text=text.replace(token,block)
  else:
   block=''.join(f"7'd{i}:alpha_label=64'h{sum(1<<(63-x) for x in range(64) if (i%16)*64+x in masks[i//16]):016x};\n" for i in entry['row_order'])
   assert text.count('@@LOCAL_FONT_ROWS@@\n')==1;text=text.replace('@@LOCAL_FONT_ROWS@@\n',block)
  data=text.replace('\n',entry['newline']).encode('utf8')
  try:put(entry['target'],data,entry['sha256'])
  except AssertionError as e:raise ValueError('Local font/Pillow rendering differs from frozen glyphs;no replacement was written. Use the documented matching Windows fonts,or build/validate a separate changed version: '+entry['target']) from e
  count+=1
 print('PASS restored and SHA256-checked',count,'licensed/generated inputs;no hardware operations')
if __name__=='__main__':main()
