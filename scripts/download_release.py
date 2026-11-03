"""Download public fixed-hash firmware (and optional demo);no hardware access."""
from pathlib import Path
import argparse,json,hashlib,urllib.request,subprocess,sys,tempfile,shutil
R=Path(__file__).resolve().parents[1]
TAG='alpha-1.0-artf-diagnostic-20261102'
REPO='beforecell/FPGA-Project'
DEMO_SHA='AD0CA3BCA0554AEE8FFBEDC06606D382F59477D1727655916C0A052AF6DC84F9'
def download():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--with-demo',action='store_true');a=p.parse_args()
 versions=json.loads((R/'verification/versions.json').read_text(encoding='utf8'))
 wanted={f'{role}-{m["bit_sha256"][:12]}.bit':m['bit_sha256'].upper() for role,m in versions.items()}
 if a.with_demo:wanted['Synthetic_Demo.img']=DEMO_SHA
 url=f'https://api.github.com/repos/{REPO}/releases/tags/{TAG}'
 request=lambda url:urllib.request.Request(url,headers={'User-Agent':'HX4S20C-reproduction'})
 try:
  release=json.load(urllib.request.urlopen(request(url),timeout=30))
  if release['draft']:raise ValueError('Expected a public release')
  byname={x['name']:x for x in release['assets']}
  cache=R/'runtime/release_downloads';cache.mkdir(parents=True,exist_ok=True)
  with tempfile.TemporaryDirectory(prefix='alpha_release_') as temp:
   staged={}
   for name,expected in wanted.items():
    if name not in byname:raise ValueError('Release asset missing: '+name)
    asset=byname[name]
    if asset.get('digest') and asset['digest'].lower()!='sha256:'+expected.lower():raise ValueError('Remote digest differs from pinned source: '+name)
    target=Path(temp)/name;h=hashlib.sha256();received=0
    with urllib.request.urlopen(request(asset['browser_download_url']),timeout=45) as response,target.open('wb') as out:
     for data in iter(lambda:response.read(1024*1024),b''):
      received+=len(data)
      if received>32*1024*1024:raise ValueError('Unexpected asset length')
      out.write(data);h.update(data)
    if received!=asset['size'] or h.hexdigest().upper()!=expected:raise ValueError('Downloaded bytes/SHA256 mismatch: '+name)
    staged[name]=target;print('SHA256 OK',name,flush=True)
   # Check destinations before importing any file;never overwrite local changes.
   destinations={}
   for name,src in staged.items():
    destinations[cache/name]=src
    if name=='Synthetic_Demo.img':destinations[R/'assets/Synthetic_Demo.img']=src
    else:
     role=next(role for role in versions if name.startswith(role+'-'))
     destinations[R/versions[role]['project_relative']/'blackbox.bit']=src
   for dest,src in destinations.items():
    if dest.exists() and hashlib.sha256(dest.read_bytes()).digest()!=hashlib.sha256(src.read_bytes()).digest():raise FileExistsError('Existing modified file preserved: '+str(dest))
   for dest,src in destinations.items():dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
  print('PASS public download and pinned hash import.No board/card/Flash operations.')
 except Exception as e:
  raise SystemExit('下载未完成：'+str(e)+'\n也可在GitHub Release手动下载4个bit，用import_firmware.py按哈希导入。')
if __name__=='__main__':download()
