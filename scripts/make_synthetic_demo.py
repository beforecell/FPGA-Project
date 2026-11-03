"""Own geometric test content+test tone. No precomputed analysis results."""
from pathlib import Path
import sys,argparse,math,struct
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'host'))
import numpy as np
from PIL import Image,ImageDraw
import alpha_package as pack,blackbox_studio
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=R/'assets/Synthetic_Demo.img');a=p.parse_args()
cache=a.output.parent/(a.output.stem+'_assets');cache.mkdir(parents=True,exist_ok=False)
assets=[]
def frames():
 for i in range(30):
  im=Image.new('RGB',(640,480),'#162238');d=ImageDraw.Draw(im);d.rectangle((0,240,639,479),fill='#374151')
  d.rectangle((40+i*8,280,100+i*8,340),fill='#f1b84b');yield np.array(im)
video=cache/'TEST_VIDEO.img';blackbox_studio.make_image(frames(),video,fps=30,quality='balanced',source_label='Own geometric test;not road footage')
pcm=cache/'TEST_VIDEO.pcm';pcm.write_bytes(b''.join(struct.pack('<h',int(3000*math.sin(2*math.pi*750*n/48000))) for n in range(48000)))
assets.append(pack.Asset(pack.VIDEO,'SYNTHETIC_TEST',video,640,480,30,30,1000,pcm,source='Own deterministic geometry and750Hz test tone'))
for i,color in enumerate(['#d04545','#357bb8','#3b9969','#b5832c']):
 path=cache/f'IMAGE{i+1}.bmp';im=Image.new('RGB',(640,480),color);d=ImageDraw.Draw(im)
 d.rectangle((40,40,599,439),outline='white',width=8);d.text((80,100),'SYNTHETIC IMAGE '+str(i+1),fill='white');im.save(path)
 assets.append(pack.Asset(pack.IMAGE,f'IMAGE{i+1}',path,640,480,source='Own geometric image'))
pack.build(assets,a.output);m=pack.inspect(a.output,True)
print('PASS synthetic Alpha package',a.output,m['visible'],'media.No physical-card or HDMI acceptance.')
