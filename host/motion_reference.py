"""Software preview of the bounded motion algorithm, not board telemetry."""
import cv2,numpy as np
import bb48_codec

def analyze(current,previous,threshold=24,camera=False):
    c=bb48_codec.area_half(current);p=bb48_codec.area_half(previous)
    gray=lambda a:((a.astype(np.uint32)*np.array([77,150,29],np.uint32)).sum(-1)>>8).astype(np.uint8)
    cg,pg=gray(c),gray(p);d=cv2.absdiff(cg,pg);raw=(d>threshold).astype(np.uint8)
    m=(cv2.filter2D(raw,-1,np.ones((3,3),np.uint8),borderType=cv2.BORDER_CONSTANT)>=(6 if camera else 5)).astype(np.uint8)
    m[[0,-1],:]=0;m[:,[0,-1]]=0
    grid=m.reshape(60,4,80,4).sum((1,3))>=(8 if camera else 4)
    scene='LIGHT CHANGE' if raw.sum()>19200 and abs(int(cg.sum())-int(pg.sum()))>1536000 else 'CAMERA MOTION' if (camera and m.sum()>23040) or grid.sum()>2400 else 'NORMAL'
    _,_,stats,_=cv2.connectedComponentsWithStats(grid.astype(np.uint8),connectivity=4)
    boxes=[]
    if scene=='NORMAL':
        for x,y,w,h,n in stats[1:]:
            if n>=4 and 2<=w<=64 and 2<=h<=48:boxes.append((int(n),int(x)*4,int(y)*4,int(x+w)*4-1,int(y+h)*4-1))
    boxes=sorted(boxes,key=lambda v:-v[0])[:4]
    return dict(clean=c,mask=m,boxes=boxes,scene=scene,energy=int(d.sum()),motion_pixels=int(m.sum()))

def render(current,previous,index=0,fps=30,threshold=24,crc_ok=True,camera=False):
    a=analyze(current,previous,threshold,camera);clean=a['clean'];motion=clean.copy()
    for _,x,y,r,b in a['boxes']:cv2.rectangle(motion,(x,y),(r,b),(0,255,0),1)
    mask=np.repeat((a['mask']*255)[...,None],3,-1);status=np.full((240,320,3),(16,26,36),np.uint8)
    lines=['SOFTWARE PREVIEW',f'FRAME {index} / {index/fps:.3f}s',f'MEDIA {fps} FPS / BB48',f'CRC32: {"OK" if crc_ok else "FAIL"}',a['scene'],f'MOTION PIXELS: {a["motion_pixels"]}','Not measured board FPS']
    for n,line in enumerate(lines):cv2.putText(status,line,(10,22+n*28),cv2.FONT_HERSHEY_SIMPLEX,.43,(217,232,240),1,cv2.LINE_AA)
    return np.concatenate((np.concatenate((clean,motion),1),np.concatenate((mask,status),1)),0)
