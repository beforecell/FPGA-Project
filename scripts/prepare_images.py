"""Create640x480/24-bit BMP copies;keep originals and aspect ratio.No board I/O."""
from pathlib import Path
import argparse,json,hashlib
from PIL import Image,ImageOps
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
 source=a.source.resolve();output=a.output.resolve()
 if not source.is_dir():p.error('Source must be an image directory')
 if output.exists():p.error('Output already exists;choose a new directory to preserve old files')
 files=sorted(x for x in source.iterdir() if x.is_file() and x.suffix.lower() in ('.png','.jpg','.jpeg','.bmp'))
 if not files:p.error('No supported images in source')
 # Decode all inputs before creating any output,so a bad file is caught early.
 for x in files:
  with Image.open(x) as im:im.verify()
 output.mkdir(parents=True,exist_ok=False);records=[]
 for i,x in enumerate(files,1):
  with Image.open(x) as original:
   im=ImageOps.exif_transpose(original).convert('RGB');size=im.size
   im=ImageOps.contain(im,(640,480),Image.Resampling.LANCZOS)
   canvas=Image.new('RGB',(640,480),'black');canvas.paste(im,((640-im.width)//2,(480-im.height)//2))
   target=output/f'IMAGE{i:02d}.bmp';canvas.save(target,'BMP')
  records.append(dict(source=x.name,source_size=size,output=target.name,output_size=[640,480],sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
 (output/'image-map.json').write_text(json.dumps(dict(source_changed=False,TF_written=False,records=records),ensure_ascii=False,indent=2),encoding='utf8')
 print('Prepared',len(records),'BMP copies:',output,'Originals unchanged.No TF or Flash writes.')
if __name__=='__main__':main()
