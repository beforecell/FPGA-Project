from pathlib import Path
import os,shutil

def find(name):
 local=Path(__file__).resolve().parent/'tools'/ (name+'.exe')
 if local.is_file():return str(local)
 p=shutil.which(name)
 if p:return p
 base=Path(os.environ.get('LOCALAPPDATA',''))/'ffmpeg'
 for p in sorted(base.glob('*/bin/'+name+'.exe'),reverse=True):
  if p.is_file():return str(p)
 return None
