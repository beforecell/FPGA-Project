"""Actual pixel RTL vs independent NumPy/OpenCV oracle,including primitive path.
No source analysis results are written to TF or used at board runtime.
"""
from pathlib import Path
import sys,json,subprocess,shutil,hashlib,tempfile,os,datetime
import numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'host'))
import blackbox_studio as media,bb48_codec
from difference_refine_model import old_mask,causal_output
O=R/'runtime/tests/difference_rtl';O.mkdir(parents=True,exist_ok=True)
W=Path(os.environ.get('HX4S20_TEST_WORK',str(Path(tempfile.gettempdir())/'hx4s20_difference_sim')));W.mkdir(parents=True,exist_ok=True)
bins=Path(os.environ.get('IVERILOG_BIN',str(Path(shutil.which('iverilog')).parent) if shutil.which('iverilog') else 'MISSING_IVERILOG'))
assert (bins/'iverilog.exe').exists(),'Install Icarus or set IVERILOG_BIN;not included in this package'
assert str(W).isascii(),'Set HX4S20_TEST_WORK to a writable ASCII path'
rng=np.random.default_rng(527614);cases=[]
def add(name,a,b,valid=True,quad=False):
 if quad:
  aa=np.tile(a,(2,2,1));bb=np.tile(b,(2,2,1));expected=np.tile(causal_output(a,b),(2,2))
 else:aa=a;bb=b;expected=causal_output(a,b)
 if not valid:expected[:]=False
 cases.append(dict(name=name,current=aa,previous=bb,expected=expected,valid=valid,quad=quad))
static=rng.integers(0,256,(64,96,3),dtype=np.uint8);add('static_rich_texture',static,static)
a=np.full((64,96,3),20,np.uint8);b=a.copy();a[12:54,30]=44;a[40,14:80]=44;add('thin_strokes',a,b)
assert old_mask(a,b).sum()<causal_output(a,b).sum(),'Thin-line improvement must be real'
a=np.full((64,96,3),20,np.uint8);b=a.copy();a[12:54,30]=28;add('weak_dark_stroke',a,b)
assert old_mask(a,b).sum()==0 and causal_output(a,b).sum()>0,'Weak dark contour must be retained'
a=np.full((64,96,3),20,np.uint8);b=a.copy();a[30,40]=120;add('isolated_hot_pixel',a,b);assert not cases[-1]['expected'].any()
a=np.full((64,96,3),20,np.uint8);b=a.copy();a[16:44,30:62]=130;b[16:44,24:56]=130;add('translated_object',a,b)
add('invalid_history',rng.integers(0,256,a.shape,dtype=np.uint8),rng.integers(0,256,a.shape,dtype=np.uint8),False)
add('unseen_random_pair',rng.integers(0,256,a.shape,dtype=np.uint8),rng.integers(0,256,a.shape,dtype=np.uint8))
b=rng.integers(5,120,(64,96,3),dtype=np.uint8);a=(b.astype(np.uint16)+4).astype(np.uint8);add('small_exposure_shift',a,b)
b=rng.integers(5,120,(64,96,3),dtype=np.uint8);a=(b.astype(np.uint16)+40).astype(np.uint8);add('large_exposure_shift',a,b)
# Own synthetic full/quad rasters replace private historical road inputs.
for label,base in [('synthetic_lowlight',20),('synthetic_day',90)]:
 b=np.full((480,640,3),base,np.uint8);a=b.copy()
 b[180:330,180:260]=[150,110,40];a[180:330,204:284]=[150,110,40]
 a[100:230,420]=220;b[100:230,414]=220
 if label=='synthetic_lowlight':add(label+'_full_raster',a,b)
 add(label+'_quad_raster',a[::2,::2],b[::2,::2],quad=True)
for c in cases:
 Image.fromarray(c['expected'].astype(np.uint8)*255).save(O/(c['name']+'.png'))
packed=[]
for c in cases:
 a=c['current'].astype(np.uint64);b=c['previous'].astype(np.uint64)
 v=(a[...,0]<<42)|(a[...,1]<<34)|(a[...,2]<<26)|(b[...,0]<<18)|(b[...,1]<<10)|(b[...,2]<<2)|(int(c['valid'])<<1)|c['expected']
 packed.append(v.reshape(-1))
allv=np.concatenate(packed)
(W/'vectors.hex').write_text(''.join(f'{int(v):013x}\n' for v in allv),encoding='ascii')
setup='\n'.join(f'widths[{i}]={c["current"].shape[1]};heights[{i}]={c["current"].shape[0]};modes[{i}]={int(c["quad"])};' for i,c in enumerate(cases))
bench=r'''module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,de=0,quad=0;reg[9:0]x=0;reg[8:0]y=0;reg[49:0]v=0;wire mask;
alpha_frame_difference dut(clk,rst,de,quad,v[1],x,y,v[49:26],v[25:2],8'd18,mask);
reg[49:0]vectors[0:TOTAL-1];integer widths[0:CASES-1],heights[0:CASES-1],modes[0:CASES-1];
reg expected1=0,valid1=0;integer f,j,i,n=0,checks=0,log;reg e,d;
always @(posedge clk)begin
 e=expected1;d=valid1;expected1=v[0];valid1=de&&!rst;#1;
 if(!rst&&d)begin
  if(mask!==e)$fatal(1,"difference mismatch case%0d n%0d xy%0d,%0d got%b want%b",f,n,x,y,mask,e);
  checks=checks+1;
 end
end
task tick;begin @(negedge clk);end endtask
initial begin
 SETUP
 $readmemh("vectors.hex",vectors);repeat(6)tick;rst=0;
 for(f=0;f<CASES;f=f+1)begin
  if(f%3==1)begin de=0;rst=1;repeat(3)tick;rst=0;end
  quad=modes[f];
  for(j=0;j<heights[f];j=j+1)begin
   for(i=0;i<widths[f];i=i+1)begin x=i;y=j;v=vectors[n];de=1;tick;n=n+1;end
   de=0;repeat(5+(j%4))tick;
  end
  de=0;repeat(8)tick;
 end
 repeat(5)tick;if(checks!=TOTAL)$fatal(1,"pixel count%0d",checks);
 $display("PASS %0d exact pixels,full/quad seams,source pair validity,thin/static/noise/exposure,two-clock pipeline",checks);$finish;
end
endmodule'''.replace('TOTAL',str(len(allv))).replace('CASES',str(len(cases))).replace('SETUP',setup)
(W/'tb.sv').write_text(bench,encoding='utf8')
primitive=r'''`undef __ICARUS__
module EG_LOGIC_BRAM #(parameter DATA_WIDTH_A=32,DATA_WIDTH_B=32,ADDR_WIDTH_A=10,ADDR_WIDTH_B=10,
 DATA_DEPTH_A=1024,DATA_DEPTH_B=1024,BYTE_ENABLE=0,MODE="DP",REGMODE_A="NOREG",REGMODE_B="NOREG",
 WRITEMODE_A="NORMAL",WRITEMODE_B="NORMAL",RESETMODE="SYNC",IMPLEMENT="32K")(
 input clka,cea,wea,rsta,ocea,input[DATA_WIDTH_A-1:0]dia,input[ADDR_WIDTH_A-1:0]addra,input bea,
 output[DATA_WIDTH_A-1:0]doa,input clkb,ceb,web,rstb,oceb,input[DATA_WIDTH_B-1:0]dib,input[ADDR_WIDTH_B-1:0]addrb,input beb,
 output reg[DATA_WIDTH_B-1:0]dob);
 reg[DATA_WIDTH_A-1:0]mem[0:DATA_DEPTH_A-1];
 initial if(ADDR_WIDTH_A!=10||IMPLEMENT!="32K"||(DATA_WIDTH_A!=4&&DATA_WIDTH_A!=2))$fatal(1,"wrong RAM contract");
 always @(posedge clka)if(cea&&wea)mem[addra]<=dia;
 always @(posedge clkb)if(ceb)dob<=mem[addrb];
 assign doa=0;
endmodule'''
(W/'primitive.v').write_text(primitive,encoding='utf8')
files=[R/'fpga/player/rtl/alpha_frame_difference.v',R/'fpga/player/rtl/bb3_ram.v']
for p in files:shutil.copy2(p,W/p.name)
records=[]
for implementation in ['behavioral','primitive_mixed']:
 extras=[W/'primitive.v'] if implementation=='primitive_mixed' else []
 cmd=[str(bins/'iverilog.exe'),'-g2012','-s','tb','-o',str(W/(implementation+'.vvp')),str(W/'tb.sv'),*map(str,extras),str(W/'alpha_frame_difference.v'),str(W/'bb3_ram.v')]
 p=subprocess.run(cmd,capture_output=True,text=True,encoding='utf8',errors='replace',creationflags=0x08000000)
 (O/(implementation+'_compile.log')).write_text(p.stdout+p.stderr,encoding='utf8');assert p.returncode==0,p.stderr
 p=subprocess.run([str(bins/'vvp.exe'),str(W/(implementation+'.vvp'))],cwd=W,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=180,creationflags=0x08000000)
 (O/(implementation+'.log')).write_text(p.stdout+p.stderr,encoding='utf8');print(implementation,p.stdout.strip(),flush=True);assert p.returncode==0,p.stdout+p.stderr
 records.append(dict(implementation=implementation,status='PASS',stdout=p.stdout))
(O/'checks.json').write_text(json.dumps(dict(status='PASS',scope='Actual pixel RTL and both memory branches vs independent reference;not physical HDMI',pixels=int(len(allv)),cases=[dict(name=c['name'],width=c['current'].shape[1],height=c['current'].shape[0],white_pixels=int(c['expected'].sum())) for c in cases],records=records,source_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in files}),ensure_ascii=False,indent=2),encoding='utf8')
print('PASS candidate pixels and ERAM read contracts;no board or TF operation')
