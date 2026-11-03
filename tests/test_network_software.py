"""Network transport faults,transaction verification and Chinese output names.
All sockets/cards in this test are models. No device or host IP operations.
"""
from pathlib import Path
import sys,json,socket,time,struct,threading,tempfile,hashlib,datetime,io
from unittest.mock import patch,Mock
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'host'))
import network_transport as net,protocol,transfers,alpha_package as package,tf_gui,device_tools
from PIL import Image
CID=bytes.fromhex('00112233445566778899AABBCCDDEEFF')
card=protocol.Card(True,False,False,0,CID,bytes(16),2048,0)
cases=[]

class FakeSocket:
 def __init__(self):
  self.queue=[];self.storage={};self.armed=False;self.range=(0,0);self.sent=0;self.deliveries=0
  self.drop_once=True;self.corrupt_once=True;self.applied=set();self.attempts={};self.is_open=True
 def sendto(self,raw,peer):
  self.sent+=1;kind,sid,inner=net.decode(raw);cmd,seq,lba,p=protocol.decode(inner)
  self.attempts[seq]=self.attempts.get(seq,0)+1;status=0;body=b''
  if cmd==protocol.ARM:
   n=int.from_bytes(p[:4],'little')
   if p[4:]!=CID or lba+n>card.sectors:status=6
   else:self.armed=True;self.range=(lba,lba+n)
  elif cmd==protocol.DISARM:self.armed=False
  elif cmd==protocol.WRITE:
   if not self.armed or not self.range[0]<=lba<self.range[1]:status=6
   else:
    self.storage[lba]=p;self.applied.add((lba,p))
    if self.drop_once:self.drop_once=False;return
  elif cmd==protocol.READ:body=self.storage.get(lba,bytes(512))
  elif cmd==protocol.PING:body=p
  reply=net.encode(131,sid,protocol.encode(cmd|128,seq,lba,bytes([status])+body))
  # Reverse delivery order exercises matching by seq/LBA rather than arrival.
  if self.corrupt_once and cmd==protocol.READ:
   q=bytearray(reply);q[-1]^=1;self.queue.insert(0,(bytes(q),peer));self.corrupt_once=False
  else:self.queue.insert(0,(reply,peer))
 def recvfrom(self,n):
  if self.queue:self.deliveries+=1;return self.queue.pop(0)
  time.sleep(.001);raise socket.timeout()
 def close(self):self.is_open=False

s=FakeSocket();c=net.Client(s,('192.0.2.20',net.PORT),123,net.Adapter('test',1,'169.254.1.1',16),timeout=.005,retries=3)
c.packet_gap=0
c.arm(card,100,16)
blocks=[bytes((i+j)&255 for j in range(512)) for i in range(16)]
assert c.write_sectors(100,blocks)==16
assert len(s.applied)==16 and c.retry_count>=1
assert c.read_sectors(100,16)==blocks and c.rx_corrupt_frames==1
cases.append('window8,out_of_order,ACK_loss,corrupt_reply,retry_same_data')
c.disarm()
try:c.write_sector(100,bytes(512))
except protocol.BoardError as e:assert e.status==6
else:raise AssertionError('unarmed write accepted')
cases.append('write_range_authorization')
cancel=threading.Event();cancel.set();sent=s.sent
try:c.read_sectors(100,8,cancel=cancel)
except InterruptedError:pass
else:raise AssertionError('cancel ignored')
assert s.sent==sent
cases.append('cancel_before_send')
bad=bytearray(net.encode(1,1,b'abc'));bad[-1]^=1
try:net.decode(bad)
except protocol.FrameCRCError:pass
else:raise AssertionError('CRC accepted')
cases.append('envelope_CRC_rejection')
assert net.propose_ip(net.Adapter('Other PC',4,'192.168.77.15',24))=='192.168.77.200'
assert net.propose_ip(net.Adapter('Other PC',4,'192.168.77.200',24))=='192.168.77.199'
assert net.propose_ip(net.Adapter('Link local',11,'169.254.1.5',16))=='169.254.50.20'
cases.append('temporary_board_address_adapts_to_different_host_IPs')

class MemoryCard:
 def __init__(self):self.data={};self.writes=[];self.retry_count=0;self.armed=False;self.batch_calls=0;self.corrupt=False
 def info(self):return card
 def arm(self,*args):self.armed=True
 def disarm(self):self.armed=False
 def write_sector(self,lba,data):assert self.armed;self.data[lba]=data;self.writes.append(lba)
 def write_sectors(self,lba,blocks,cancel=None):
  self.batch_calls+=1
  for i,b in enumerate(blocks):self.write_sector(lba+i,b)
 def read_sector(self,lba):return self.data[lba]
 def read_sectors(self,lba,n,cancel=None):
  out=[self.data[lba+i] for i in range(n)]
  if self.corrupt:out[0]=bytes([out[0][0]^1])+out[0][1:]
  return out
with tempfile.TemporaryDirectory(prefix='network_software_') as tmp:
 d=Path(tmp);source=d/'fixture.img';raw=bytes((i*17)&255 for i in range(90*512));source.write_bytes(raw)
 details=dict(bytes=len(raw),sectors=90,sha256=hashlib.sha256(raw).hexdigest(),compatible=True,commit_lba=0)
 events=[];memory=MemoryCard();record=d/'record.json'
 result=transfers.write_image(memory,source,card,details,threading.Event(),lambda **kw:events.append(kw),record)
 assert result['status']=='VERIFIED' and result['readback_sha256']==details['sha256']
 assert memory.writes[0]==0 and memory.writes[-1]==0 and memory.batch_calls==3
 assert result['header_committed'] and result['transport']=='uart'
 assert events[-1]['overall_done']==len(raw)*2
 cases.append('batched_full_image_commit_last_and_complete_SHA256')
 memory.corrupt=True
 try:transfers.write_image(memory,source,card,details,threading.Event(),record=record)
 except ValueError:pass
 else:raise AssertionError('corrupt card accepted')
 assert json.loads(record.read_text())['status']=='FAILED_INCOMPLETE'
 cases.append('readback_corruption_never_success')
 memory.corrupt=False
 exported=d/'export.img';result=transfers.export_range(memory,exported,2,70,card,threading.Event())
 assert exported.read_bytes()==raw[2*512:72*512] and result['status']=='EXPORTED'
 cases.append('batched_export_actual_bytes_and_file_SHA256')
 # Real packager with Chinese path/name reproduces the former ASCII failure.
 folder=d/'中文目录';folder.mkdir();bmp=folder/'测试图.bmp';Image.new('RGB',(2,2),'blue').save(bmp)
 image=folder/'中文镜像.img'
 package.build([package.Asset(package.IMAGE,'IMAGE01',bmp,2,2)],image)
 package.inspect(image,True)
 assert '中文镜像.img' in image.with_suffix('.sha256').read_text(encoding='utf8')
 cases.append('real_packager_Chinese_directory_and_SHA256_filename')
 td=d/'中文工具/td_commands_prompt.exe';td.parent.mkdir();td.write_bytes(b'test-only-not-executed')
 with patch.object(device_tools,'CONFIG',d/'settings.json'),patch.object(device_tools,'TD',device_tools.TD):
  device_tools.configure_td(td);assert device_tools.find_td()==td
  proc=Mock();proc.stdout=io.BytesIO(b'PASS: TD returned exit code 0\n');proc.wait.return_value=0
  with patch.object(device_tools,'verify_build',return_value=dict(bit_sha256='A'*64)), \
       patch.object(device_tools.subprocess,'Popen',return_value=proc) as spawn:
   device_tools.download(d,lambda s:None)
   args=spawn.call_args.args[0];assert args[args.index('-TDExe')+1]==str(td)
 cases.append('configured_TD_path_passed_to_background_download_without_execution')
percent,label=tf_gui.progress_display(dict(phase='写入',done=512,total=1024,started=0,overall_done=512,overall_total=2048,overall_started=0),1)
assert percent==25 and '写入＋校验' in label
cases.append('overall_write_plus_readback_progress')
out=R/'runtime/tests/network_host/software_checks.json';out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps(dict(status='PASS',utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),scope='Host fault/card models and actual small packager;no physical network,card or FPGA operations',cases=cases),ensure_ascii=False,indent=2),encoding='utf8')
print('PASS network software:',len(cases),'cases;modeled faults,SHA256 and real Chinese-name packaging')
