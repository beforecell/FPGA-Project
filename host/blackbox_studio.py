"""HXBBX005 BlackBox Studio: BB48 encoder, sector images and software preview.

This program never writes a physical disk. The unified Windows GUI invokes a separate confirmed UAC helper to
write the resulting whole-disk .img after explicit removable-card selection.
CRC32 detects accidental corruption. Authenticity requires an independently
trusted signed manifest; CRC32 alone is not cryptographic tamper protection.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
import shutil
import struct
import sys
import time
import zlib

import cv2
import numpy as np

import bb48_codec as codec
import media_pipeline

W,H=640,480
HEADER_LBA,DATA_LBA=2337,4096
FRAME_SECTORS=451
BMP_SECTORS=1801
MAGIC=b'HXBBX005'
FRAME_MAGIC=b'BBFRAME5'


def sha256(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
    return h.hexdigest()


def fit_rgb(bgr):
    return media_pipeline.fit_rgb(bgr)


def video_frames(source,fps=30,max_frames=65535):
    yield from media_pipeline.frames(source,fps,max_frames)


def video_assets(source):
    return media_pipeline.posters(source)


def _car(a,cx,cy,scale,color):
    cx,cy=int(cx),int(cy);s=float(scale)
    def pt(x,y):return (int(cx+x*s),int(cy+y*s))
    cv2.ellipse(a,pt(0,17),(max(1,int(34*s)),max(1,int(8*s))),0,0,360,(17,19,23),-1,cv2.LINE_AA)
    cv2.fillConvexPoly(a,np.array([pt(-31,12),pt(-29,-12),pt(-17,-29),pt(17,-29),pt(29,-12),pt(31,12)]),color,cv2.LINE_AA)
    cv2.fillConvexPoly(a,np.array([pt(-22,-12),pt(-13,-25),pt(13,-25),pt(22,-12)]),(26,44,61),cv2.LINE_AA)
    cv2.line(a,pt(-28,-2),pt(28,-2),tuple(min(255,c+25) for c in color),max(1,int(2*s)),cv2.LINE_AA)
    cv2.rectangle(a,pt(-30,8),pt(-22,18),(12,14,18),-1)
    cv2.rectangle(a,pt(22,8),pt(30,18),(12,14,18),-1)
    cv2.rectangle(a,pt(-25,1),pt(-15,6),(255,42,31),-1)
    cv2.rectangle(a,pt(15,1),pt(25,6),(255,42,31),-1)
    cv2.rectangle(a,pt(-9,7),pt(9,12),(225,227,212),-1)


def demo_frame(index,count=240,fps=30):
    """Original procedural driving/tunnel/event scene, not recorded evidence."""
    yy,xx=np.indices((H,W));t=index/fps
    sky=np.clip(1-yy[...,None]/300,0,1)
    upper=np.array([39,95,145]);lower=np.array([197,213,210])
    a=(lower+(upper-lower)*sky).astype(np.uint8)
    cv2.circle(a,(512,87),25,(252,230,164),-1,cv2.LINE_AA)
    # Stable city silhouette and changing foreground road give distinct spatial
    # frequency content while keeping deterministic source generation.
    for j in range(32):
        bx=j*23-27;bh=28+(j*47)%97
        color=(75+(j*9)%35,100+(j*7)%30,113+(j*11)%24)
        cv2.rectangle(a,(bx,221-bh),(bx+19,225),color,-1)
        for wy in range(230-bh,216,12):
            for wx in range(bx+4,bx+17,7):cv2.rectangle(a,(wx,wy),(wx+2,wy+4),(185,199,182),-1)
    cv2.fillPoly(a,[np.array([[0,224],[640,224],[640,480],[0,480]])],(63,91,62))
    center=320+int(5*math.sin(t*.8));horizon=222
    cv2.fillConvexPoly(a,np.array([[center-35,horizon],[center+35,horizon],[630,480],[10,480]]),(58,63,68))
    cv2.fillConvexPoly(a,np.array([[center-36,horizon],[center-32,horizon],[25,480],[5,480]]),(231,226,193))
    cv2.fillConvexPoly(a,np.array([[center+32,horizon],[center+36,horizon],[635,480],[615,480]]),(231,226,193))
    phase=(index*0.075)%1
    for lane in (-1,1):
        for k in range(8):
            z=((k+phase)/8)**2;z2=min(1,((k+phase+.36)/8)**2)
            py=horizon+int(z*258);qy=horizon+int(z2*258)
            px=center+int(lane*(12+91*z));qx=center+int(lane*(12+91*z2))
            cv2.line(a,(px,py),(qx,qy),(222,223,203),max(1,int(2+5*z)),cv2.LINE_AA)
    for side in (-1,1):
        for k in range(6):
            z=((k+.5+phase)/6.8)**2
            px=center+int(side*(45+330*z));py=horizon+int(z*240)
            height=int(9+60*z)
            cv2.line(a,(px,py),(px,py-height),(48,50,43),max(1,height//10))
            cv2.circle(a,(px,py-height),(max(2,height//3)),(33,68,46),-1,cv2.LINE_AA)
    lead_x=center+15*math.sin(t*.6)
    _car(a,lead_x,285+2*math.sin(t),.9,(184,192,202))
    _car(a,center-145+6*math.sin(t*.7),362,1.4,(40,92,152))
    night=80<=index<160
    if night:
        # A lit tunnel: dark source retains real underlying 8-bit levels.
        shade=(a.astype(np.float32)*.13)
        cone=np.exp(-(((xx-320)/225)**2+((yy-420)/145)**2))
        shade += a.astype(np.float32)*(cone[...,None]*.48)
        a=np.clip(shade,0,255).astype(np.uint8)
        for side in (-1,1):
            cv2.line(a,(center+side*65,183),(center+side*310,0),(60,60,48),9,cv2.LINE_AA)
            for k in range(5):
                z=((k+phase)/5)**2
                px=center+int(side*(51+220*z));py=198-int(180*z)
                cv2.ellipse(a,(px,py),(int(3+5*z),int(2+3*z)),0,0,360,(253,228,147),-1,cv2.LINE_AA)
    # High-speed cross-lane vehicle and a sudden impact/light discontinuity.
    if 172<=index<200:
        p=(index-172)/27
        _car(a,720-690*p,320+55*p,1.2+1.15*p,(201,50,34))
    if 188<=index<=191:
        flash=(192-index)/4
        a=np.clip(a.astype(np.float32)*(1-flash*.65)+255*flash*.65,0,255).astype(np.uint8)
    if index>=192:
        shift=int(12*math.sin((index-192)*1.8)*math.exp(-(index-192)/12))
        a=cv2.warpAffine(a,np.float32([[1,0,shift],[0,1,abs(shift)//2]]),(W,H),borderMode=cv2.BORDER_REFLECT)
    # Vehicle hood, camera labels, timestamp; the label explicitly identifies
    # this as synthetic test imagery to avoid confusion with real recordings.
    cv2.ellipse(a,(320,515),(235,72),0,180,360,(23,29,35),-1,cv2.LINE_AA)
    cv2.line(a,(110,469),(530,469),(86,92,96),1,cv2.LINE_AA)
    cv2.rectangle(a,(0,0),(639,31),(8,14,22),-1)
    cv2.circle(a,(18,15),4,(255,66,52),-1,cv2.LINE_AA)
    cv2.putText(a,'BLACKBOX // SYNTHETIC DRIVING TEST',(31,21),cv2.FONT_HERSHEY_SIMPLEX,.5,(219,231,235),1,cv2.LINE_AA)
    phase_name='NIGHT / TUNNEL' if night else ('EVENT / BRAKE' if index>=172 else 'DAY / CRUISE')
    cv2.putText(a,phase_name,(15,56),cv2.FONT_HERSHEY_SIMPLEX,.46,(247,211,105),1,cv2.LINE_AA)
    cv2.putText(a,f'CAM 01 | {index:06d} | 12:06:{int(t):02d}.{int((t%1)*1000):03d}',(14,447),cv2.FONT_HERSHEY_SIMPLEX,.48,(238,240,229),1,cv2.LINE_AA)
    cv2.putText(a,f'640 x 480  {fps} FPS',(440,447),cv2.FONT_HERSHEY_SIMPLEX,.42,(238,240,229),1,cv2.LINE_AA)
    return a


def ssim_luma(a,b):
    x=cv2.cvtColor(a,cv2.COLOR_RGB2GRAY).astype(np.float64)
    y=cv2.cvtColor(b,cv2.COLOR_RGB2GRAY).astype(np.float64)
    ux=cv2.GaussianBlur(x,(11,11),1.5);uy=cv2.GaussianBlur(y,(11,11),1.5)
    vx=cv2.GaussianBlur(x*x,(11,11),1.5)-ux*ux
    vy=cv2.GaussianBlur(y*y,(11,11),1.5)-uy*uy
    vxy=cv2.GaussianBlur(x*y,(11,11),1.5)-ux*uy
    return float(np.mean(((2*ux*uy+6.5025)*(2*vxy+58.5225))/((ux*ux+uy*uy+6.5025)*(vx+vy+58.5225))))


def make_image(frames,path,fps=30,threshold=24,assets=None,source_label='custom',progress=None,quality='balanced',cancel=None):
    if not 1<=fps<=60:raise ValueError('fps范围1..60，默认30；高于30需另行验证实际链路')
    if not 0<=threshold<=255:raise ValueError('阈值范围0..255')
    path=pathlib.Path(path);manifest_path=path.with_suffix('.manifest.json')
    if path.exists() or manifest_path.exists():raise FileExistsError(f'拒绝覆盖已有文件：{path}')
    path.parent.mkdir(parents=True,exist_ok=True)
    records=[];snapshots=[];metrics=[];chain=bytes(32)
    try:
        with path.open('xb') as f:
            f.seek(DATA_LBA*512)
            for i,rgb in enumerate(frames):
                if cancel and cancel.is_set():raise InterruptedError('已取消视频制作')
                if i>=65535:raise ValueError('当前FPGA容器最多65535帧；请分段编码')
                payload=codec.encode_frame(rgb,quality=quality)
                crc=zlib.crc32(payload)&0xffffffff
                frame_header=bytearray(512);frame_header[:8]=FRAME_MAGIC
                struct.pack_into('<IQIII',frame_header,8,i,round(i*1000000/fps),len(payload),crc,2)
                struct.pack_into('<I',frame_header,36,round(i*1000000/fps)//1000)
                f.write(frame_header);f.write(payload)
                digest=hashlib.sha256(bytes(frame_header)+payload).digest()
                chain=hashlib.sha256(chain+digest).digest()
                records.append({'frame_id':i,'lba':DATA_LBA+i*FRAME_SECTORS,'pts_us':round(i*1000000/fps),
                                'crc32':f'{crc:08x}','frame_sha256':digest.hex(),'chain_sha256':chain.hex()})
                decoded=codec.decode_frame(payload)
                metric={'frame_id':i,'psnr_rgb_db':codec.psnr(rgb,decoded)}
                hardware_rgb=codec.unpack_565(codec.decode_565(payload))
                metric['psnr_rgb565_scanout_db']=codec.psnr(rgb,hardware_rgb)
                if i%20==0:
                    metric['ssim_luma_11x11']=ssim_luma(rgb,decoded)
                    metric['ssim_rgb565_scanout_luma_11x11']=ssim_luma(rgb,hardware_rgb)
                metrics.append(metric)
                if i<4:snapshots.append(rgb.copy())
                elif i in (80,150,188):snapshots[{80:1,150:2,188:3}[i]]=rgb.copy()
                if progress:progress(i+1)
            if not records:raise ValueError('没有读取到视频帧')
            bmp_lba=((DATA_LBA+len(records)*FRAME_SECTORS+31)//32)*32
            f.seek(bmp_lba*512)
            chosen=list(assets) if assets is not None else snapshots
            while len(chosen)<4:chosen.append(chosen[-1].copy())
            bmp_records=[]
            bmp_dir=path.parent/(path.stem+'_BMP_assets');bmp_dir.mkdir(exist_ok=True)
            for i,rgb in enumerate(chosen[:4]):
                if np.asarray(rgb).shape!=(H,W,3):raise ValueError('BMP必须640x480RGB')
                ok,encoded=cv2.imencode('.bmp',cv2.cvtColor(rgb,cv2.COLOR_RGB2BGR))
                if not ok:raise RuntimeError('BMP编码失败')
                b=encoded.tobytes()
                if len(b)!=921654 or struct.unpack_from('<I',b,10)[0]!=54:raise RuntimeError('BMP格式并非54字节头24位BI_RGB')
                name=f'poster_{i+1:02d}.bmp';(bmp_dir/name).write_bytes(b)
                f.write(b);f.write(bytes(BMP_SECTORS*512-len(b)))
                bmp_records.append({'index':i,'filename':name,'lba':bmp_lba+i*BMP_SECTORS,'bytes':len(b),
                                    'sectors':BMP_SECTORS,'sha256':hashlib.sha256(b).hexdigest(),
                                    'pixel_crc32':f'{zlib.crc32(b[54:])&0xffffffff:08x}'})
            end=f.tell();f.truncate(max(64*1024*1024,math.ceil(end/(1024*1024))*1024*1024))
            header=bytearray(512);header[:8]=MAGIC
            struct.pack_into('<IHHIIIHH',header,8,5,W,H,len(records),FRAME_SECTORS,DATA_LBA,fps,0)
            header[32]=threshold;struct.pack_into('<II',header,36,4,bmp_lba)
            struct.pack_into('<I',header,44,2)
            for i,bmp in enumerate(bmp_records):struct.pack_into('<I',header,48+4*i,int(bmp['pixel_crc32'],16))
            f.seek(HEADER_LBA*512);f.write(header)
        psnrs=np.array([m['psnr_rgb_db'] for m in metrics]);ssims=[m['ssim_luma_11x11'] for m in metrics if 'ssim_luma_11x11' in m]
        scanout_psnrs=np.array([m['psnr_rgb565_scanout_db'] for m in metrics])
        scanout_ssims=[m['ssim_rgb565_scanout_luma_11x11'] for m in metrics if 'ssim_rgb565_scanout_luma_11x11' in m]
        meta={'format':'HXBBX005','version':5,'source':source_label,'width':W,'height':H,'fps':fps,
              'frames':len(records),'frame_sectors':FRAME_SECTORS,'data_lba':DATA_LBA,'header_lba':HEADER_LBA,
              'codec':'BB48_4x2_RGB_OPAQUE','quality':quality,'payload_bytes_per_frame':codec.FRAME_BYTES,'threshold':threshold,
              'image_bytes':path.stat().st_size,'image_sha256':sha256(path),'final_chain_sha256':chain.hex(),
              'frame_records':records,'bmp_assets':bmp_records,'frame_quality':metrics,
              'quality_summary':{'psnr_rgb_min_db':float(psnrs.min()),'psnr_rgb_mean_db':float(psnrs.mean()),
                                 'psnr_rgb_max_db':float(psnrs.max()),'ssim_luma_mean':float(np.mean(ssims)),
                                 'ssim_sample_count':len(ssims),
                                 'psnr_rgb565_scanout_min_db':float(scanout_psnrs.min()),
                                 'psnr_rgb565_scanout_mean_db':float(scanout_psnrs.mean()),
                                 'psnr_rgb565_scanout_max_db':float(scanout_psnrs.max()),
                                 'ssim_rgb565_scanout_luma_mean':float(np.mean(scanout_ssims))},
              'integrity_notice':'CRC32 is error detection, not cryptographic authenticity. A trusted external manifest/signature is required.',
              'physical_board_tested':False}
        manifest_path.write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
        path.with_suffix('.sha256').write_text(f'{meta["image_sha256"]}  {path.name}\n',encoding='ascii')
        return meta
    except Exception:
        path.unlink(missing_ok=True)
        raise


def read_header(path):
    with open(path,'rb') as f:f.seek(HEADER_LBA*512);b=f.read(512)
    if len(b)!=512 or b[:8]!=MAGIC:raise ValueError('部署文件不是第三版格式，请使用配套的改进版固件')
    version,w,h,count,sectors,lba,fps,flags=struct.unpack_from('<IHHIIIHH',b,8)
    bmp_count,bmp_lba=struct.unpack_from('<II',b,36)
    if (version,w,h,sectors,lba,bmp_count)!=(5,W,H,FRAME_SECTORS,DATA_LBA,4) or struct.unpack_from('<I',b,44)[0]!=2:raise ValueError('不支持的镜像头')
    if not 1<=count<=65535 or not 1<=fps<=60 or flags!=0 or bmp_lba<lba+count*sectors:raise ValueError('非法镜像布局或超过FPGA的65535帧上限')
    if pathlib.Path(path).stat().st_size<(bmp_lba+bmp_count*BMP_SECTORS)*512:raise ValueError('镜像已截断')
    return {'version':version,'width':w,'height':h,'frames':count,'sectors':sectors,'lba':lba,'fps':fps,
            'threshold':b[32],'bmp_count':bmp_count,'bmp_lba':bmp_lba,
            'bmp_pixel_crc32':list(struct.unpack_from('<IIII',b,48))}


def read_payload(path,index,header=None,verify=True):
    h=header or read_header(path)
    if not 0<=index<h['frames']:raise IndexError(index)
    with open(path,'rb') as f:
        f.seek((h['lba']+index*h['sectors'])*512);b=f.read(512);payload=f.read(codec.FRAME_BYTES)
    if len(b)!=512 or b[:8]!=FRAME_MAGIC:raise ValueError(f'帧{index}头损坏')
    frame_id,pts,size,expected_crc,codec_id=struct.unpack_from('<IQIII',b,8)
    if (frame_id,size,codec_id)!=(index,codec.FRAME_BYTES,2):raise ValueError(f'帧{index}字段错误')
    crc=zlib.crc32(payload)&0xffffffff
    ok=len(payload)==codec.FRAME_BYTES and crc==expected_crc
    if verify and not ok:raise ValueError(f'帧{index} CRC错误 expected={expected_crc:08x},actual={crc:08x}')
    return payload,{'frame_id':frame_id,'pts_us':pts,'timestamp_ms':struct.unpack_from('<I',b,36)[0],
                    'expected_crc32':expected_crc,'actual_crc32':crc,'crc_ok':ok}


def verify_image(path,manifest=True):
    h=read_header(path);bad=[];chain=bytes(32);records=[]
    with open(path,'rb') as f:
        for i in range(h['frames']):
            f.seek((h['lba']+i*h['sectors'])*512);b=f.read(512);payload=f.read(codec.FRAME_BYTES)
            try:
                _,state=read_payload(path,i,h,verify=False)
                if not state['crc_ok']:bad.append(i)
            except ValueError:bad.append(i)
            digest=hashlib.sha256(b+payload).digest();chain=hashlib.sha256(chain+digest).digest()
            records.append(digest.hex())
        bmp_checks=[]
        for i in range(4):
            f.seek((h['bmp_lba']+i*BMP_SECTORS)*512);bmp=f.read(921654)
            valid=(bmp[:2]==b'BM' and struct.unpack_from('<iiHHI',bmp,18)==(W,H,1,24,0))
            pixel_crc=zlib.crc32(bmp[54:])&0xffffffff
            bmp_checks.append({'index':i,'valid_24bit_BMP':valid,'sha256':hashlib.sha256(bmp).hexdigest(),
                               'pixel_crc32':f'{pixel_crc:08x}','pixel_crc32_ok':pixel_crc==h['bmp_pixel_crc32'][i]})
    report={'header':h,'frames_checked':h['frames'],'crc_bad_frames':bad,'bmp_checks':bmp_checks,
            'computed_chain_sha256':chain.hex(),'image_sha256':sha256(path)}
    mp=pathlib.Path(path).with_suffix('.manifest.json')
    if manifest and mp.exists():
        original=json.loads(mp.read_text(encoding='utf-8'))
        report['manifest_image_sha256_ok']=original['image_sha256']==report['image_sha256']
        report['manifest_chain_sha256_ok']=original['final_chain_sha256']==chain.hex()
        report['manifest_record_count_ok']=len(original.get('frame_records',[]))==h['frames']
        report['manifest_frame_sha256_bad']=[i for i,entry in enumerate(original['frame_records']) if i>=len(records) or entry['frame_sha256']!=records[i]]
    report['ok']=not bad and all(x['valid_24bit_BMP'] and x['pixel_crc32_ok'] for x in bmp_checks) and report.get('manifest_image_sha256_ok',True) and report.get('manifest_chain_sha256_ok',True) and not report.get('manifest_frame_sha256_bad',[]) and report.get('manifest_record_count_ok',True)
    return report


def render_views(rgb,previous,trail=None,index=0,fps=30,threshold=24,crc_ok=True):
    from motion_reference import render
    return render(rgb,previous,index,fps,threshold,crc_ok),None


def preview(path):
    h=read_header(path);index=0;paused=False;trail=None;previous=None
    window='BlackBox Studio software reference | SPACE pause | A/D step | Q quit'
    while True:
        payload,state=read_payload(path,index,h,verify=False);rgb=codec.decode_frame(payload)
        if previous is None:previous=rgb
        view,trail=render_views(rgb,previous,trail,index,h['fps'],h['threshold'],state['crc_ok'])
        cv2.imshow(window,cv2.cvtColor(view,cv2.COLOR_RGB2BGR))
        key=cv2.waitKey(max(1,round(1000/h['fps'])))&255
        if key in (27,ord('q')):break
        if key==32:paused=not paused
        previous=rgb
        if key==ord('a'):index=(index-1)%h['frames'];paused=True
        elif key==ord('d'):index=(index+1)%h['frames'];paused=True
        elif not paused:index=(index+1)%h['frames']
    cv2.destroyAllWindows()


def sign_manifest(manifest,key_path,signature_path):
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    key=serialization.load_pem_private_key(pathlib.Path(key_path).read_bytes(),password=None)
    if not isinstance(key,Ed25519PrivateKey):raise ValueError('需要Ed25519私钥PEM')
    pathlib.Path(signature_path).write_bytes(key.sign(pathlib.Path(manifest).read_bytes()))


def verify_signature(manifest,public_key,signature):
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    key=serialization.load_pem_public_key(pathlib.Path(public_key).read_bytes())
    if not isinstance(key,Ed25519PublicKey):raise ValueError('需要Ed25519公钥PEM')
    key.verify(pathlib.Path(signature).read_bytes(),pathlib.Path(manifest).read_bytes())
    return True


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    c=sub.add_parser('convert');c.add_argument('source');c.add_argument('output');c.add_argument('--fps',type=int,default=30);c.add_argument('--max-frames',type=int,default=65535);c.add_argument('--threshold',type=int,default=24)
    d=sub.add_parser('demo');d.add_argument('output');d.add_argument('--frames',type=int,default=240);d.add_argument('--fps',type=int,default=30)
    for command in ('inspect','verify','preview'):
        a=sub.add_parser(command);a.add_argument('image')
    r=sub.add_parser('render');r.add_argument('image');r.add_argument('output');r.add_argument('--frame',type=int,default=188)
    s=sub.add_parser('sign');s.add_argument('manifest');s.add_argument('private_key');s.add_argument('signature')
    v=sub.add_parser('verify-signature');v.add_argument('manifest');v.add_argument('public_key');v.add_argument('signature')
    args=p.parse_args()
    def status(i):
        if i%30==0:print(f'Encoded {i} frames',flush=True)
    if args.command=='convert':
        meta=make_image(video_frames(args.source,args.fps,args.max_frames),args.output,args.fps,args.threshold,assets=video_assets(args.source),source_label=str(args.source),progress=status)
        print(json.dumps({k:v for k,v in meta.items() if k not in ('frame_records','frame_quality')},ensure_ascii=False,indent=2))
    elif args.command=='demo':
        meta=make_image((demo_frame(i,args.frames,args.fps) for i in range(args.frames)),args.output,args.fps,
                        assets=[demo_frame(i,args.frames,args.fps) for i in (0,100,160,188)],source_label='Original synthetic driving / tunnel / collision test',progress=status)
        print(json.dumps({k:v for k,v in meta.items() if k not in ('frame_records','frame_quality')},ensure_ascii=False,indent=2))
    elif args.command=='inspect':print(json.dumps(read_header(args.image),ensure_ascii=False,indent=2))
    elif args.command=='verify':
        report=verify_image(args.image);print(json.dumps(report,ensure_ascii=False,indent=2));sys.exit(0 if report['ok'] else 2)
    elif args.command=='preview':preview(args.image)
    elif args.command=='render':
        h=read_header(args.image);previous=None;trail=None
        for i in range(max(0,args.frame-12),args.frame+1):
            payload,state=read_payload(args.image,i,h,verify=False);rgb=codec.decode_frame(payload)
            if previous is None:previous=rgb
            view,trail=render_views(rgb,previous,trail,i,h['fps'],h['threshold'],state['crc_ok']);previous=rgb
        cv2.imwrite(args.output,cv2.cvtColor(view,cv2.COLOR_RGB2BGR))
    elif args.command=='sign':sign_manifest(args.manifest,args.private_key,args.signature);print('Signed manifest; protect the private key and distribute the public key independently.')
    elif args.command=='verify-signature':verify_signature(args.manifest,args.public_key,args.signature);print('Ed25519 manifest signature verified.')


if __name__=='__main__':main()
