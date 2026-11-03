"""Independent spatial reference for runtime frame-difference refinement.
Used only for tests/reference figures,never packaged on TF or read by FPGA.
"""
import numpy as np,cv2

def gray(rgb):
    return ((rgb.astype(np.uint32)*np.array([77,150,29],np.uint32)).sum(-1)>>8).astype(np.uint8)

def old_mask(current,previous,threshold=18):
    d=np.abs(gray(current).astype(np.int16)-gray(previous).astype(np.int16))
    raw=d>threshold
    votes=raw.astype(np.uint8)+np.roll(raw,1,1)+np.roll(raw,1,0)+np.roll(np.roll(raw,1,0),1,1)
    out=raw&(votes>=3);out[0,:]=False;out[:,0]=False
    return out

def two_of_four(current,previous):
    c=gray(current);d=np.abs(c.astype(np.int16)-gray(previous).astype(np.int16))
    raw=d>np.where(c<64,8,16)
    votes=raw.astype(np.uint8)+np.roll(raw,1,1)+np.roll(raw,1,0)+np.roll(np.roll(raw,1,0),1,1)
    out=raw&(votes>=2);out[0,:]=False;out[:,0]=False
    return out

def refined_mask(current,previous,threshold=18,contour=True,dark_low=6,dark_high=12,bright_low=10):
    c=gray(current);d=np.abs(c.astype(np.int16)-gray(previous).astype(np.int16)).astype(np.uint8)
    dark=c<64;low=np.where(dark,dark_low,bright_low)
    high=np.where(dark,dark_high,threshold)
    weak=d>low;strong=d>high
    votes=cv2.filter2D(weak.astype(np.uint8),-1,np.ones((3,3),np.uint8),borderType=cv2.BORDER_CONSTANT)
    near=cv2.dilate(strong.astype(np.uint8),np.ones((3,3),np.uint8),borderType=cv2.BORDER_CONSTANT).astype(bool)
    span=cv2.dilate(d,np.ones((3,3),np.uint8))-cv2.erode(d,np.ones((3,3),np.uint8))
    def shifted(dx,dy):
        out=np.roll(np.roll(weak,dy,0),dx,1)
        if dy>0:out[:dy]=False
        elif dy<0:out[dy:]=False
        if dx>0:out[:,:dx]=False
        elif dx<0:out[:,dx:]=False
        return out
    gap=(shifted(-1,0)&shifted(1,0))|(shifted(0,-1)&shifted(0,1))|\
        (shifted(-1,-1)&shifted(1,1))|(shifted(1,-1)&shifted(-1,1))
    keep=weak&(votes>=2)&(near|((votes>=3)&(span>=4)))
    filled=keep|(~weak&gap&near&(span>=4))
    if not contour:return filled
    # Local support retains coherent weak changes without retaining a lone
    # hot pixel. The second stage draws the inner boundary of this mask.
    motion=(votes>=2)&(near|((votes>=3)&(votes<9)))
    eroded=cv2.erode(motion.astype(np.uint8),cv2.getStructuringElement(cv2.MORPH_CROSS,(3,3)),borderType=cv2.BORDER_CONSTANT)
    return motion&~eroded.astype(bool)


def causal_output(current,previous,threshold=18):
    """Each causal3x3 neighborhood contributes one line/column of context.
    The two neighborhoods produce a2screen-pixel spatial shift,
    not an extra frame delay.
    """
    center=refined_mask(current,previous,threshold)
    out=np.zeros_like(center);out[4:,4:]=center[2:-2,2:-2]
    return out
