"""Actual new RTL + existing HXTF core;abstract SD512-byte storage model."""
from pathlib import Path
import sys,subprocess,json,hashlib,struct,socket,datetime,shutil,os,tempfile
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'host'))
import protocol,network_transport as net
O=R/'runtime/tests/network_rtl';O.mkdir(parents=True,exist_ok=True)
SID=0x10203040;CID=bytes.fromhex('00112233445566778899AABBCCDDEEFF')
packets=[]
def hello(sid):return net.encode(net.HELLO,sid,socket.inet_aton('192.0.2.10')+struct.pack('!H',50000)+socket.inet_aton('192.0.2.20'))
def data(seq,cmd,lba=0,payload=b'',sid=SID):return net.encode(net.DATA,sid,protocol.encode(cmd,seq,lba,payload))
packets=[hello(SID),data(1,protocol.PING,payload=b'network-test'),data(2,protocol.INFO),data(3,protocol.ARM,100,struct.pack('<I',16)+CID)]
packets += [data(4+i,protocol.WRITE,100+i,bytes(((100+i+j)&255) for j in range(512))) for i in range(8)]
packets += [data(12+i,protocol.READ,100+i) for i in range(8)]
packets += [data(20,protocol.DISARM),data(100,protocol.WRITE,108,bytes(512),sid=SID-1)]
bad=bytearray(data(101,protocol.WRITE,108,bytes(512)));bad[-1]^=1
packets += [bytes(bad),data(21,protocol.WRITE,108,bytes(512)),hello(SID+1),data(102,protocol.WRITE,108,bytes(512)),data(22,protocol.INFO,sid=SID+1)]
flat=b''.join(packets);(O/'rx.hex').write_text('\n'.join(f'{b:02x}' for b in flat)+'\n',encoding='ascii')
starts=[];offset=0
for p in packets:starts.append(offset);offset+=len(p)
setup='\n'.join(f'starts[{i}]={s};lens[{i}]={len(p)};' for i,(s,p) in enumerate(zip(starts,packets)))
tb=r'''module tb;
reg clk=0;always #10 clk=~clk;reg rst=1;
reg[7:0]rx_data;reg rx_valid=0;reg[15:0]rx_length=0;wire[7:0]tx_data;wire tx_valid,tx_request;wire[15:0]tx_length;
reg ack=0;integer cooldown=0;wire udp_ready=cooldown==0;reg[15:0]held_length;
wire[31:0]local_ip,peer_ip,dropped,accepted;wire[15:0]peer_port;wire[4:0]queued;
wire[7:0]crx,ctx;wire crv,ctv,ctr,armed,active,soft_reset,core_fault;
wire sd_start,sd_write;wire[31:0]sd_lba,discarded;reg sd_busy=0,sd_done=0,sd_valid=0;reg[7:0]sd_data=0;
wire[8:0]write_addr;wire[7:0]write_data;reg[9:0]sd_n=0;reg[7:0]storage[0:4095];integer write_count=0;
assign write_addr=sd_n[8:0];
network_bridge dut(clk,rst,rx_data,rx_valid,rx_length,udp_ready,ack,tx_data,tx_valid,tx_request,tx_length,
 local_ip,peer_ip,peer_port,crx,crv,ctx,ctv,ctr,armed,1'b1,4'd0,core_fault,dropped,accepted,queued);
tf_bridge_core #(.BAUD(0)) core(clk,rst|core_fault,crx,crv,ctx,ctv,ctr,sd_start,sd_write,sd_lba,
 1'b1,sd_busy,sd_done,4'd0,128'h00112233445566778899aabbccddeeff,128'd0,64'd1024,
 sd_data,sd_valid,write_addr,write_data,soft_reset,armed,active,discarded,32'd0,32'd0);
always @(posedge clk)begin
 ack<=tx_request&&udp_ready;
 sd_done<=0;sd_valid<=0;
 if(sd_start)begin sd_busy<=1;sd_n<=0;if(sd_write)write_count<=write_count+1;end
 else if(sd_busy)begin
  if(sd_n<512)begin
   if(sd_write)storage[{sd_lba[2:0],sd_n[8:0]}]<=write_data;
   else begin sd_data<=storage[{sd_lba[2:0],sd_n[8:0]}];sd_valid<=1;end
   sd_n<=sd_n+1'b1;
  end else if(sd_n==512)sd_n<=513;
  else begin sd_busy<=0;sd_done<=1;end
 end
 if(queued>16)$fatal(1,"queue overflow");
end
integer fd,n=0,packet_count=0;
always @(posedge clk)begin
 if(cooldown>0)begin
  if(tx_length!=held_length)$fatal(1,"TX length changed while vendor MAC still consumes packet");
  cooldown=cooldown-1;
 end
 if(tx_valid)begin
  $fwrite(fd,"%02x",tx_data);
  if(n+1==tx_length)begin $fwrite(fd,"\n");n=0;packet_count=packet_count+1;held_length=tx_length;cooldown=1500;end else n=n+1;
 end
end
reg[7:0]rx_bytes[0:TOTAL-1];integer starts[0:CASES-1];integer lens[0:CASES-1];integer i,j,k;
task send_packet;input integer which;begin
 for(j=0;j<lens[which];j=j+1)begin @(negedge clk);if(j>=2)rx_length=lens[which];rx_valid=1;rx_data=rx_bytes[starts[which]+j];end
 @(negedge clk);rx_valid=0;repeat(4)@(negedge clk);
end endtask
task await_count;input integer wanted;begin
 k=0;while(packet_count<wanted && k<200000)begin @(negedge clk);k=k+1;end
 if(packet_count!=wanted)$fatal(1,"reply timeout wanted%0d got%0d,state%0d,accepted%0d,dropped%0d",wanted,packet_count,dut.state,accepted,dropped);
end endtask
initial begin
 SETUP
 $readmemh("rx.hex",rx_bytes);fd=$fopen("tx.hex","w");repeat(8)@(negedge clk);rst=0;
 send_packet(0);await_count(1);
 send_packet(1);await_count(2);send_packet(2);await_count(3);send_packet(3);await_count(4);
 for(i=4;i<12;i=i+1)send_packet(i);await_count(12);
 for(i=12;i<20;i=i+1)send_packet(i);await_count(20);
 send_packet(20);await_count(21);
 send_packet(21);send_packet(22);repeat(500)@(negedge clk);if(packet_count!=21)$fatal(1,"stale/CRC packet responded");
 send_packet(23);await_count(22);send_packet(24);await_count(23);
 send_packet(25);send_packet(26);await_count(24);
 repeat(100)@(negedge clk);
 if(write_count!=8)$fatal(1,"unauthorized or duplicate writes%0d",write_count);
 if(dropped!=1)$fatal(1,"outer CRC rejection missing");
 $fclose(fd);$display("PASS real bridge/core,window8 read/write,CRC,session and range gates,writes%0d",write_count);$finish;
end
initial begin #50000000;$fatal(1,"global timeout");end
endmodule'''.replace('TOTAL',str(len(flat))).replace('CASES',str(len(packets))).replace('SETUP',setup)
(O/'tb.sv').write_text(tb,encoding='utf8')
W=Path(os.environ.get('HX4S20_TEST_WORK',str(Path(tempfile.gettempdir())/'hx4s20_network_sim')));W.mkdir(parents=True,exist_ok=True)
if not str(W).isascii():raise RuntimeError('Icarus需要英文临时路径；请将HX4S20_TEST_WORK设为可写的英文目录')
for n in ['tb.sv','rx.hex']:shutil.copy2(O/n,W/n)
compiler=os.environ.get('IVERILOG_BIN')
if compiler:bins=Path(compiler)
elif shutil.which('iverilog'):bins=Path(shutil.which('iverilog')).parent
else:bins=Path('MISSING_IVERILOG')
if not (bins/'iverilog.exe').is_file():raise RuntimeError('请安装Icarus并加入PATH，或设置IVERILOG_BIN指向其bin目录')
rtl=R/'fpga/tf-maintenance/rtl/network_bridge.v';core=R/'fpga/uart-maintenance/rtl/tf_bridge_core.v'
shutil.copy2(core,W/'tf_bridge_core.v')
shutil.copy2(rtl,W/'network_bridge.v')
cmd=[str(bins/'iverilog.exe'),'-g2012','-s','tb','-o',str(W/'test.vvp'),str(W/'tb.sv'),str(W/'network_bridge.v'),str(W/'tf_bridge_core.v')]
p=subprocess.run(cmd,capture_output=True,text=True,encoding='utf8',errors='replace',creationflags=0x08000000);assert p.returncode==0,p.stderr
p=subprocess.run([str(bins/'vvp.exe'),str(W/'test.vvp')],cwd=W,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=40,creationflags=0x08000000)
(O/'simulation.log').write_text(p.stdout+p.stderr,encoding='utf8');assert p.returncode==0,p.stdout+p.stderr
shutil.copy2(W/'tx.hex',O/'tx.hex')
rows=[net.decode(bytes.fromhex(line)) for line in (O/'tx.hex').read_text().splitlines()];assert len(rows)==24,len(rows)
replies={}
for kind,sid,payload in rows:
 if kind==129:assert payload[:4]==b'NTF1';continue
 cmd,seq,lba,payload=protocol.decode(payload);replies[seq]=(cmd,lba,payload)
assert replies[1][2][1:13]==b'network-test'
for i in range(8):
 assert replies[4+i][2][0]==0
 assert replies[12+i][2][0]==0
 assert replies[12+i][2][1:513]==bytes(((100+i+j)&255) for j in range(512))
assert replies[21][2][0]==6
assert 100 not in replies and 101 not in replies and 102 not in replies
(O/'checks.json').write_text(json.dumps(dict(status='PASS',scope='Real network_bridge and tf_bridge_core RTL;UDP transport timing and SD storage abstract;not RGMII or physical SD proof',responses=len(rows),writes=8,window=8,source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [rtl,core]},stdout=p.stdout),indent=2),encoding='utf8')
print(p.stdout.strip());print('PASS host decode of all24 real RTL replies,sector bytes and rejected unauthorized writes')
