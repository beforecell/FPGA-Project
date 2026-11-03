"""Opaque4x2 blocks: two RGB565 endpoints + eight2bit selectors =48bits.

This is the version5 board format, NOT standard BC1. Splitting each4x4 region
into two independently fitted4x2 blocks improves real-edge/color separation at
6bpp (6.912MB/s payload at640x480x30). No temporal dependency or hidden boxes.
"""
import numpy as np
import bc1_codec as bc1
WIDTH,HEIGHT=640,480
FRAME_BYTES=230400
DTYPE=np.dtype([('endpoints','<u4'),('selectors','<u2')])
rgb_to_565,unpack_565,psnr=bc1.rgb_to_565,bc1.unpack_565,bc1.psnr

def _blocks(rgb):
 return np.asarray(rgb).reshape(240,2,160,4,3).transpose(0,2,1,3,4).reshape(-1,8,3)

def encode_frame(rgb,iterations=4,quality='balanced'):
 rgb=np.asarray(rgb)
 if rgb.shape!=(480,640,3) or rgb.dtype!=np.uint8:raise ValueError('expected640x480 RGB uint8')
 endpoints=[]
 for half in (rgb[:240],rgb[240:]):
  # Repeated rows let the validated BC1 least-squares fitter optimize the
  # same8 samples with equal weights. Only endpoints are retained.
  packet=bc1.encode_frame(np.repeat(half,2,axis=0),iterations=8 if quality=='high' else iterations)
  endpoints.append(np.frombuffer(packet,dtype='<u4').reshape(-1,2)[:,0])
 words=np.concatenate(endpoints);p0=(words&65535).astype(np.uint16);p1=(words>>16).astype(np.uint16)
 pixels=_blocks(rgb).astype(np.int32)
 def evaluate(a,b):
  colors=bc1.palette(a,b).astype(np.int32)
  distance=((pixels[:,:,None,:]-colors[:,None,:,:])**2).sum(axis=3)
  return distance.min(axis=2).sum(axis=1),distance.argmin(axis=2).astype(np.uint32)
 best,codes=evaluate(p0,p1)
 if quality=='high':
  # Quantized endpoint neighbourhood refinement. Preserve the best result
  # block-by-block; this cannot worsen the selected squared RGB error.
  for endpoint in (0,1):
   for shift,maxval in ((11,31),(5,63),(0,31)):
    for step in (-1,1):
     base=p0 if endpoint==0 else p1
     part=((base.astype(np.int32)>>shift)&maxval)+step
     candidate=((base.astype(np.uint32)&np.uint32(65535^(maxval<<shift)))|
                (np.clip(part,0,maxval).astype(np.uint32)<<shift)).astype(np.uint16)
     a,b=bc1.ordered_endpoints(candidate,p1) if endpoint==0 else bc1.ordered_endpoints(p0,candidate)
     err,_=evaluate(a,b);better=err<best
     p0=np.where(better,a,p0).astype(np.uint16);p1=np.where(better,b,p1).astype(np.uint16);best=np.minimum(best,err)
 _,codes=evaluate(p0,p1)
 out=np.empty(len(p0),dtype=DTYPE)
 out['endpoints']=p0.astype(np.uint32)|(p1.astype(np.uint32)<<16)
 out['selectors']=(codes<<(2*np.arange(8,dtype=np.uint32))).sum(axis=1,dtype=np.uint32).astype(np.uint16)
 return out.tobytes()

def decode_frame(payload):
 if len(payload)!=FRAME_BYTES:raise ValueError('BB48载荷长度应为230400字节')
 b=np.frombuffer(payload,dtype=DTYPE);e=b['endpoints'];s=b['selectors'].astype(np.uint32)
 palette=bc1.palette((e&65535).astype(np.uint16),(e>>16).astype(np.uint16))
 codes=(s[:,None]>>(2*np.arange(8,dtype=np.uint32)))&3
 pixels=palette[np.arange(len(b))[:,None],codes]
 return pixels.reshape(240,160,2,4,3).transpose(0,2,1,3,4).reshape(480,640,3)

def decode_565(payload):
 a=decode_frame(payload).astype(np.uint16)
 return ((a[:,:,0]>>3)<<11)|((a[:,:,1]>>2)<<5)|(a[:,:,2]>>3)

def area_half(rgb):
 a=np.asarray(rgb,dtype=np.uint16)
 return ((a[::2,::2]+a[::2,1::2]+a[1::2,::2]+a[1::2,1::2]+2)>>2).astype(np.uint8)
