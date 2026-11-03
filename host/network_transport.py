"""Network-only board TF transport. No disk handles or host IPv4 changes.

HXTN wraps the existing HXTF commands, preserving CID/range authorization.
Bulk transfers pipeline a bounded window; each ACK follows actual SD completion.
The standard reproduction topology is one board directly on one Ethernet NIC.
"""
from __future__ import annotations
import dataclasses,ipaddress,json,secrets,socket,struct,subprocess,threading,time,zlib
import protocol

PORT=49192
MAGIC=b'HXTN';HEADER=struct.Struct('<4sBBHI')
HELLO,DATA=1,3
MAX_WINDOW=8

def encode(kind,session,payload):
    raw=HEADER.pack(MAGIC,1,kind,len(payload),session)+payload
    return raw+struct.pack('<I',zlib.crc32(raw)&0xffffffff)

def decode(raw):
    if len(raw)<16:raise protocol.ProtocolError('网络报文过短')
    magic,version,kind,n,session=HEADER.unpack_from(raw)
    if magic!=MAGIC or version!=1 or n>576 or len(raw)!=n+16:raise protocol.ProtocolError('网络报文头或长度无效')
    if zlib.crc32(raw[:-4])&0xffffffff!=int.from_bytes(raw[-4:],'little'):raise protocol.FrameCRCError('网络报文CRC不符')
    return kind,session,raw[12:-4]

@dataclasses.dataclass(frozen=True)
class Adapter:
    name:str
    index:int
    ip:str
    prefix:int
    mac:str=''
    link_speed:str=''

def list_adapters():
    """Read Windows NIC configuration without changing addresses or routes."""
    script=r'''$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.UTF8Encoding]::new();$r=@(Get-NetAdapter -Physical | Where-Object {$_.Status -eq 'Up' -and $_.MediaType.ToString() -eq '802.3'} | ForEach-Object {$a=$_;Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {$_.AddressState -eq 'Preferred'} | ForEach-Object {[pscustomobject]@{name=$a.Name;index=$a.ifIndex;ip=$_.IPAddress;prefix=$_.PrefixLength;mac=$a.MacAddress;link_speed=$a.LinkSpeed}}});ConvertTo-Json -InputObject $r -Compress'''
    p=subprocess.run(['powershell.exe','-NoProfile','-Command',script],capture_output=True,timeout=15,creationflags=0x08000000)
    # Windows PowerShell writes console output in the active OEM page. Force
    # UTF-8 in the script so Chinese NIC names survive different machines.
    if p.returncode:raise RuntimeError('无法读取有线网卡配置：'+p.stderr.decode('gb18030','replace'))
    try:rows=json.loads(p.stdout.decode('utf8'))
    except (UnicodeDecodeError,json.JSONDecodeError):rows=json.loads(p.stdout.decode('gb18030'))
    return [Adapter(**v) for v in (rows or [])]

def propose_ip(adapter):
    network=ipaddress.IPv4Network(f'{adapter.ip}/{adapter.prefix}',strict=False)
    if network.prefixlen>30:raise ValueError('所选网卡子网没有足够地址；请使用普通网线直连网卡')
    # This is a temporary board address, never an address applied to Windows.
    count=network.num_addresses
    offset=0x3214 if network==ipaddress.IPv4Network('169.254.0.0/16') else min(200,count-2)
    candidate=network.network_address+offset
    if candidate==ipaddress.IPv4Address(adapter.ip):candidate=network.network_address+(offset-1 if offset>1 else 2)
    return str(candidate)

def open_socket(adapter):
    s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    try:
        s.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1)
        if hasattr(socket,'SO_EXCLUSIVEADDRUSE'):s.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
        s.bind((adapter.ip,0));s.settimeout(.05)
        if hasattr(socket,'IP_UNICAST_IF'):
            s.setsockopt(socket.IPPROTO_IP,socket.IP_UNICAST_IF,struct.pack('!I',adapter.index))
        elif __import__('os').name=='nt':
            s.setsockopt(socket.IPPROTO_IP,31,struct.pack('!I',adapter.index))
        return s
    except BaseException:s.close();raise

class SocketPort:
    """Compatibility with GUI lifecycle checks;this never opens a COM port."""
    def __init__(self,s):self.socket=s;self.is_open=True
    def close(self):self.socket.close();self.is_open=False

class Client(protocol.Client):
    def __init__(self,sock,peer,session,adapter,timeout=1.5,retries=4,log=None):
        super().__init__(SocketPort(sock),timeout,retries,log)
        self.socket=sock;self.peer=peer;self.session=session;self.adapter=adapter
        self.window=MAX_WINDOW;self.channel='ethernet';self.datagrams_sent=0
        self.packet_gap=.000025;self._last_send=0.0
    def _send(self,inner):
        # Pace the small UDP requests as well as the large writes. The
        # supplied50MHz IP parser cannot absorb minimum-gap1Gbps microbursts.
        deadline=self._last_send+self.packet_gap
        while time.perf_counter()<deadline:pass
        self.socket.sendto(encode(DATA,self.session,inner),self.peer);self.datagrams_sent+=1
        self._last_send=time.perf_counter()
    def _receive(self):
        try:raw,peer=self.socket.recvfrom(2048)
        except socket.timeout:return None
        if peer!=self.peer:return None
        try:
            kind,session,payload=decode(raw)
            if kind!=(DATA|128) or session!=self.session:return None
            return protocol.decode(payload)
        except protocol.ProtocolError:
            self.rx_corrupt_frames+=1;return None
    def _batch(self,requests,cancel=None):
        """Bounded sliding window. Retry identical seq/LBA/data, never new data."""
        requests=iter(requests);pending={};results={};exhausted=False
        with self.lock:
            while pending or not exhausted:
                if cancel is not None and cancel.is_set():exhausted=True
                while not exhausted and len(pending)<self.window:
                    try:identity,command,lba,payload=next(requests)
                    except StopIteration:exhausted=True;break
                    self.seq=(self.seq+1)&0xffffffff
                    frame=protocol.encode(command,self.seq,lba,payload)
                    pending[self.seq]=dict(identity=identity,command=command,lba=lba,frame=frame,sent=time.monotonic(),attempts=0)
                    self._send(frame)
                if not pending:break
                reply=self._receive()
                if reply:
                    command,seq,lba,payload=reply;v=pending.get(seq)
                    if v and command==(v['command']|128) and lba==v['lba']:
                        if not payload:raise protocol.ProtocolError('网络应答缺少SD状态')
                        if payload[0]:raise protocol.BoardError(payload[0],payload[1:])
                        results[v['identity']]=payload[1:];del pending[seq]
                now=time.monotonic()
                for v in pending.values():
                    if now-v['sent']>=self.timeout:
                        if v['attempts']>=self.retries:raise TimeoutError('网络维护应答超时；本次镜像未完成校验')
                        self._send(v['frame']);v['sent']=now;v['attempts']+=1;self.retry_count+=1
                        self.log(f"网络重传 LBA={v['lba']} 第{v['attempts']}次")
        if cancel is not None and cancel.is_set():raise InterruptedError('已取消网络传输；已发送的窗口已收尾，镜像未完成校验')
        return results
    def exchange(self,command,lba=0,payload=b''):
        return self._batch([(0,command,lba,payload)])[0]
    def write_sectors(self,start,data,cancel=None):
        blocks=list(data)
        if not blocks or len(blocks)>64 or any(len(b)!=512 for b in blocks):raise ValueError('批写范围须为1..64个完整扇区')
        self._batch(((i,protocol.WRITE,start+i,b) for i,b in enumerate(blocks)),cancel)
        return len(blocks)
    def read_sectors(self,start,count,cancel=None):
        if not 1<=count<=64:raise ValueError('批读范围须为1..64扇区')
        result=self._batch(((i,protocol.READ,start+i,b'') for i in range(count)),cancel)
        out=[]
        for i in range(count):
            b=result[i]
            if len(b)<512 or any(b[512:]):raise protocol.ProtocolError('网络读回扇区长度无效')
            out.append(b[:512])
        return out

def connect(adapter,log=None,timeout=5):
    sock=open_socket(adapter);session=secrets.randbits(32) or 1;proposal=propose_ip(adapter)
    payload=socket.inet_aton(adapter.ip)+struct.pack('!H',sock.getsockname()[1])+socket.inet_aton(proposal)
    hello=encode(HELLO,session,payload);deadline=time.monotonic()+timeout;last_send=0
    try:
        while time.monotonic()<deadline:
            if time.monotonic()-last_send>.4:
                sock.sendto(hello,('255.255.255.255',PORT))
                sock.sendto(hello,(proposal,PORT));last_send=time.monotonic()
            try:raw,peer=sock.recvfrom(2048)
            except socket.timeout:continue
            try:kind,sid,body=decode(raw)
            except protocol.ProtocolError:continue
            if kind!=(HELLO|128) or sid!=session or len(body)!=16 or body[:4]!=b'NTF1':continue
            if socket.inet_ntoa(body[4:8])!=proposal or peer[1]!=PORT:continue
            client=Client(sock,peer,session,adapter,log=log)
            if client.ping(b'HX4S20C network TF')!=b'HX4S20C network TF':raise protocol.ProtocolError('网络回环校验失败')
            card=client.info()
            if not card.initialized:card=client.reinitialize()
            return client,card
        raise TimeoutError('未发现网络维护固件；确认千兆直连链路并先加载网络维护程序。电脑IPv4设置未改动。')
    except BaseException:sock.close();raise
