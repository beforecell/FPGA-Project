"""Board-only serial transport. Never opens a Windows physical disk."""
from __future__ import annotations
import dataclasses, struct, time, threading, secrets, zlib

MAGIC=b'HXTF'; HEADER=struct.Struct('<4sBBIIH'); MAX_PAYLOAD=556
INFO,READ,WRITE,ARM,DISARM,PING,REINIT=range(1,8)

class ProtocolError(Exception): pass
class FrameCRCError(ProtocolError): pass
class BoardError(ProtocolError):
    def __init__(self,status,detail=b''):
        self.status,self.detail=status,detail
        labels={1:'通信CRC错误',2:'不支持的协议或命令',3:'数据长度错误',4:'TF未就绪',5:'扇区超出容量',6:'未确认写入范围、卡身份不符或卡已写保护',7:'序号冲突',8:'SD操作失败',9:'SD返回长度错误'}
        super().__init__(labels.get(status,f'设备错误{status}')+(f'，SD错误码{detail.hex()}' if detail else ''))

def encode(command,seq,lba=0,payload=b''):
    if len(payload)>MAX_PAYLOAD: raise ValueError('payload too large')
    raw=HEADER.pack(MAGIC,1,command,seq,lba,len(payload))+payload
    return raw+struct.pack('<I',zlib.crc32(raw[4:])&0xffffffff)

def decode(raw):
    if len(raw)<20:raise ProtocolError('short frame')
    magic,version,command,seq,lba,n=HEADER.unpack_from(raw)
    if magic!=MAGIC or version!=1 or n>MAX_PAYLOAD or len(raw)!=20+n:raise ProtocolError('invalid frame')
    if zlib.crc32(raw[4:-4])&0xffffffff!=struct.unpack_from('<I',raw,len(raw)-4)[0]:raise FrameCRCError('reply CRC32 mismatch')
    return command,seq,lba,raw[16:-4]

@dataclasses.dataclass(frozen=True)
class Card:
    initialized:bool; armed:bool; busy:bool; error:int; cid:bytes; csd:bytes; sectors:int; baud:int; debug1:int=0; debug2:int=0
    @property
    def capacity(self):return self.sectors*512
    @property
    def identity(self):return self.cid.hex().upper()
    @property
    def name(self):return self.cid[3:8].decode('ascii','replace')

class Client:
    def __init__(self,serial_port,timeout=3.0,retries=3,log=None):
        self.port=serial_port;self.timeout=timeout;self.retries=retries;self.log=log or (lambda s:None)
        self.seq=secrets.randbits(31);self.buffer=bytearray();self.lock=threading.RLock();self.retry_count=0;self.rx_corrupt_frames=0

    def _frame(self,deadline):
        while time.monotonic()<deadline:
            start=self.buffer.find(MAGIC)
            if start<0:
                if len(self.buffer)>3:del self.buffer[:-3]
            elif start:del self.buffer[:start]
            if self.buffer[:4]==MAGIC and len(self.buffer)>=16:
                if self.buffer[4]!=1:
                    del self.buffer[0];continue
                n=int.from_bytes(self.buffer[14:16],'little')
                if n>MAX_PAYLOAD:del self.buffer[0];continue
                if len(self.buffer)>=20+n:
                    raw=bytes(self.buffer[:20+n])
                    try:frame=decode(raw)
                    except ProtocolError:
                        # A truncated/corrupt packet may contain the beginning
                        # of the next valid retry. Keep that retry intact.
                        del self.buffer[0];self.rx_corrupt_frames+=1
                        self.log('接收帧CRC/格式异常，逐字节重同步；未接受损坏数据')
                        continue
                    del self.buffer[:20+n];return frame
            data=self.port.read(max(1,getattr(self.port,'in_waiting',0)))
            if data:self.buffer.extend(data)
        raise TimeoutError('等待FPGA应答超时')

    def exchange(self,command,lba=0,payload=b''):
        if len(payload)>512:raise ValueError('request payload maximum 512 bytes')
        with self.lock:
            self.seq=(self.seq+1)&0xffffffff;seq=self.seq;raw=encode(command,seq,lba,payload)
            for attempt in range(self.retries+1):
                if attempt:self.retry_count+=1;self.log(f'重传 seq={seq} cmd={command} lba={lba} 第{attempt}次')
                # Stop-and-wait: this is a new command or an identical retry.
                # Discard only incomplete local parser state, so a truncated
                # large reply cannot hide a later short ACK indefinitely.
                self.buffer.clear()
                self.port.write(raw);self.port.flush()
                deadline=time.monotonic()+self.timeout
                try:
                    while True:
                        cmd,s,block,result=self._frame(deadline)
                        if (cmd,s,block)!=(command|128,seq,lba):continue
                        if not result:raise ProtocolError('response lacks status')
                        if result[0]==1:raise FrameCRCError('FPGA报告接收CRC错误')
                        if result[0]:raise BoardError(result[0],result[1:])
                        return result[1:]
                except (TimeoutError,FrameCRCError):
                    if attempt==self.retries:raise
            raise AssertionError('unreachable')

    def info(self):
        p=self.exchange(INFO)
        if len(p)<58 or p[:4]!=b'TFM1' or any(p[58:]):raise ProtocolError('这不是本工具配套的TF维护固件')
        return Card(bool(p[4]&1),bool(p[4]&2),bool(p[4]&4),p[5],p[6:22],p[22:38],int.from_bytes(p[38:46],'little'),int.from_bytes(p[46:50],'little'),int.from_bytes(p[50:54],'little'),int.from_bytes(p[54:58],'little'))

    def reinitialize(self,timeout=8):
        self.exchange(REINIT);deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            card=self.info()
            if card.initialized and card.sectors:return card
            if card.error and not card.busy:raise ProtocolError(f'TF初始化失败：SD错误{card.error:X}，诊断{card.debug1:08X}/{card.debug2:08X}；未写卡')
            time.sleep(.05)
        raise TimeoutError('TF初始化超时；检查卡是否插好，再重新进入维护模式')

    def read_sector(self,lba):
        p=self.exchange(READ,lba)
        if len(p)<512 or any(p[512:]):raise ProtocolError('sector read length or padding error')
        return p[:512]

    def write_sector(self,lba,data):
        if len(data)!=512:raise ValueError('must write complete 512-byte sector')
        self.exchange(WRITE,lba,data)

    def arm(self,card,start,count):
        if not card.initialized or count<=0 or start<0 or start+count>card.sectors:raise ValueError('invalid card write range')
        self.exchange(ARM,start,struct.pack('<I',count)+card.cid)

    def disarm(self):return self.exchange(DISARM)
    def ping(self,data):
        p=self.exchange(PING,payload=data)
        if len(p)<len(data) or any(p[len(data):]):raise ProtocolError('PING padding error')
        return p[:len(data)]

def list_devices():
    from serial.tools import list_ports
    return [p for p in list_ports.comports() if p.vid==0x1a86 and p.pid==0x7523]

def connect(device,log=None):
    import serial
    if device not in [p.device for p in list_devices()]:raise ProtocolError('只能选择已识别的板载CH340串口；不连接蓝牙串口')
    port=serial.Serial(device,1000000,timeout=.05,write_timeout=3,rtscts=False,dsrdtr=False)
    try:
        port.reset_input_buffer();client=Client(port,log=log)
        if client.ping(b'HX4S20C TF maintenance')!=b'HX4S20C TF maintenance':raise ProtocolError('loopback mismatch')
        deadline=time.monotonic()+8
        card=client.info()
        while card.busy and not card.initialized and time.monotonic()<deadline:
            time.sleep(.05);card=client.info()
        if not card.initialized or not card.sectors:card=client.reinitialize()
        return client,card
    except Exception:port.close();raise
