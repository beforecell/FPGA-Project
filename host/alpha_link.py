"""Versioned Alpha telemetry and acknowledged player controls, UART 115200 8N1.

This protocol never writes SD sectors. TF maintenance uses protocol.py instead.
"""
import time,struct,zlib

class StatusDecoder:
 def __init__(self):self.buffer=bytearray()
 def feed(self,data):
  self.buffer.extend(data);out=[]
  while len(self.buffer)>=8:
   candidates=[n for n in (self.buffer.find(b'ALPHAST1'),self.buffer.find(b'ALPHAST2'),self.buffer.find(b'ALPHAST3'),self.buffer.find(b'ALPHAST4'),self.buffer.find(b'ALPHAST5'),self.buffer.find(b'ALPHAST6'),self.buffer.find(b'ALPHAST7')) if n>=0]
   if not candidates:
    del self.buffer[:-7];break
   n=min(candidates)
   if n:del self.buffer[:n]
   version=int(chr(self.buffer[7]));size={1:32,2:56,3:64,4:84,5:88,6:92,7:92}[version]
   if len(self.buffer)<size:break
   p=bytes(self.buffer[:size])
   if zlib.crc32(p[:-4])&0xffffffff!=int.from_bytes(p[-4:],'little'):
    del self.buffer[0];continue
   del self.buffer[:size]
   s=dict(status='ALPHA_STATUS_RECEIVED',version=version,catalog_ready=bool(p[8]&128),
    browser=bool(p[8]&1),fullscreen=bool(p[8]&64),image_mode=bool(p[8]&32),
    media_ready=bool(p[8]&16),playing=bool(p[8]&8),announcing=bool(p[8]&4),loading=bool(p[8]&2),
    error=p[9],resource_count=p[10],selected=p[11],frame_id=int.from_bytes(p[12:14],'little'),
    fps=int.from_bytes(p[14:16],'little'),media_ms=int.from_bytes(p[16:20],'little'),
    audio_sample=int.from_bytes(p[20:24],'little'),underflows=int.from_bytes(p[24:28],'little'),raw=p.hex())
   if version>=2:
    s.update(valid_mask=int.from_bytes(p[28:30],'little'),image_mask=int.from_bytes(p[30:32],'little'),
     catalog_busy=bool(p[32]&128),selected_ready=bool(p[32]&64),selected_kind=(p[32]>>4)&3,
     key_n=p[32]&15,active_valid=bool(p[33]&1),boot_done=bool(p[33]&2),cache_valid=bool(p[33]&4),
     header_valid=bool(p[33]&8),manager_idle=bool(p[33]&16),last_short=p[34]&15,last_long=p[34]>>4,
     short_count=p[35],long_count=p[36],control_seq=p[37],control_cmd=p[38],control_status=p[39],
     asset_lba=int.from_bytes(p[40:44],'little'),asset_bytes=int.from_bytes(p[44:48],'little'),
     frame_commits=int.from_bytes(p[48:52],'little'))
   if version>=3:
    s.update(rate_q8_8=int.from_bytes(p[52:54],'little'),rate=int.from_bytes(p[52:54],'little')/256,
     root_page=bool(p[54]&1),folder_images=bool(p[54]&2),analysis_on=bool(p[54]&4),speed_mode=bool(p[54]&8),seek_busy=bool(p[54]&16),
     list_count=p[55]&15,selected_row=p[55]>>4,elapsed_samples=int.from_bytes(p[56:60],'little'))
   if version>=4:
    words=struct.unpack_from('<5I',p,60)
    s.update(runtime_tag=p[60:64].decode('ascii',errors='replace'),analysis_input_frame=words[1]&65535,motion_result_frame=words[1]>>16,
     live_pcm_count=words[2],fft_updates=words[3],fft_skipped_samples=words[4])
   if version>=5:s.update(volume_percent=p[80],motion_view_previous=bool(p[81]&1),motion_result_valid=bool(p[81]&2),photo_auto=bool(p[82]&1))
   if version>=6:s.update(exposure=p[84],contrast=p[85],brightness=p[86],adjust_mode=bool(p[87]&1),adjust_item=(p[87]>>1)&3)
   if s.get('runtime_tag') in ('ART9','ARTK','ARTD','ARTF'):
    s.update(fft_enabled=False,wave_completed_bins=s.pop('fft_updates'),wave_history_bins=s.pop('fft_skipped_samples'))
    s.update(display_view=(p[83]>>3)&3,focus=(p[83]>>1)&3,ui_zoom=bool(p[83]&1))
   if version>=7:
    # ARTK replaces four diagnostic slots,not the media clock/wave counters.
    coherent=p[56]==p[57] and bool(p[48]&4)
    s.update(keyframe_mode=bool(p[48]&1),keyframe_switch=bool(p[48]&2),keyframe_ready=bool(p[48]&4),
     keyframe_count=p[49],keyframe_action=p[50],keyframe_result=p[51],keyframes_coherent=coherent,
     keyframe_generation=p[57],keyframe_asset=p[58],
     render_analysis=bool(p[59]&4),render_view=(p[59]>>3)&3,render_full=bool(p[59]&32))
    s['keyframes']=list(struct.unpack_from('<4H',p,40))[:p[49]] if coherent and p[49]<=4 else None
    for replaced in ('asset_lba','asset_bytes','frame_commits','elapsed_samples'):s.pop(replaced,None)
   out.append(s)
  return out

def control_packet(seq,command,mask=0):
 if not 1<=seq<=255:raise ValueError('sequence must be 1..255')
 if not (((command in (1,2)) and mask in (1,2,4,8)) or (command in (3,4) and mask==0) or (command==5 and 0<=mask<=100)):
  raise ValueError('unsupported player control')
 payload=bytes((1,seq,command,mask))
 return b'AK'+payload+struct.pack('<I',zlib.crc32(payload)&0xffffffff)

def read_status(port,seconds):
 decoder=StatusDecoder();deadline=time.monotonic()+seconds
 while time.monotonic()<deadline:
  for s in decoder.feed(port.read(max(1,port.in_waiting))):yield s

def send_control(port,command,mask=0,timeout=2,retries=3,seq=None):
 # Same sequence on a retry: losing an ACK must not apply a key action twice.
 decoder=StatusDecoder()
 if seq is None:
  # Each GUI action may open a fresh serial session. Derive the next sequence
  # from the board, so reopening the GUI cannot randomly repeat the last key.
  deadline=time.monotonic()+timeout
  while seq is None and time.monotonic()<deadline:
   for s in decoder.feed(port.read(max(1,port.in_waiting))):
    if s['version']<2:raise RuntimeError('当前固件没有播放器遥控，请先恢复新版Alpha播放程序')
    seq=s['control_seq']%255+1
  if seq is None:raise TimeoutError('未收到播放器状态，未发送遥控命令；请核对固件和串口')
 packet=control_packet(seq,command,mask)
 for attempt in range(retries):
  port.write(packet);port.flush();deadline=time.monotonic()+timeout
  while time.monotonic()<deadline:
   for s in decoder.feed(port.read(max(1,port.in_waiting))):
    if s.get('control_seq')!=seq or s.get('control_cmd')!=command:continue
    status=s['control_status']
    if status==0:return s
    if status==3:break  # Busy is retryable and is not cached as a successful key.
    if status==4:
     seq=seq%255+1;packet=control_packet(seq,command,mask);break
    raise RuntimeError('播放器拒绝控制命令，状态码 '+str(status))
   else:continue
   break
 raise TimeoutError('播放器未确认控制命令；不能将串口发送结束当作执行成功')

if __name__=='__main__':
 import argparse,json,serial
 parser=argparse.ArgumentParser(description='Alpha只读媒体控制；不写TF卡')
 parser.add_argument('--port',required=True);parser.add_argument('--seconds',type=float,default=3)
 parser.add_argument('--action',choices=['status','open','up','down','back','hold1','hold3','hold4','rescan'],default='status')
 args=parser.parse_args()
 import device_tools
 with device_tools.board_access(),serial.Serial(args.port,115200,timeout=.1,write_timeout=1) as port:
  if args.action!='status':
   current=next(read_status(port,2),None)
   if not current or current['version']<3:raise RuntimeError('这些按键需要 ALPHAST3 新交互固件；未发送旧版含义不同的按键')
   cmd,mask={'open':(1,2),'up':(1,4),'down':(1,8),'back':(1,1),'hold1':(2,1),'hold3':(2,4),'hold4':(2,8),'rescan':(3,0)}[args.action]
   print(json.dumps(send_control(port,cmd,mask),ensure_ascii=False))
  for s in read_status(port,args.seconds):print(json.dumps(s,ensure_ascii=False))
