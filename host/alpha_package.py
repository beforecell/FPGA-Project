import runtime_tools
"""ALPHA100 raw-sector catalog. Media encoding remains offline preparation.
No physical disks, serial ports or programming tools are opened by this module.
"""
from pathlib import Path
from dataclasses import dataclass
import struct,zlib,json,hashlib,subprocess,tempfile,wave,shutil,os,array,math,sys

MAGIC=b'ALPHA100';ENTRY=b'A1ASSET1';SECTOR=512;MAX_ENTRIES=16;MAX_MEDIA=12
VIDEO,IMAGE,VOICE=0,1,2

@dataclass
class Asset:
    kind:int
    name:str
    payload:Path
    width:int=640
    height:int=480
    fps:int=30
    frames:int=1
    duration_ms:int=0
    pcm:Path|None=None
    source:str=''

def crc(data):return zlib.crc32(data)&0xffffffff
def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def seal(b):struct.pack_into('<I',b,508,crc(b[:508]));return bytes(b)
def check(b,magic):
    if len(b)!=512 or b[:8]!=magic or crc(b[:508])!=struct.unpack_from('<I',b,508)[0]:raise ValueError('资源索引头或CRC无效')

def bmp_info(path):
    b=Path(path).read_bytes()[:54]
    if len(b)!=54 or b[:2]!=b'BM':raise ValueError('不是标准BMP')
    off,dib,w,h,planes,bpp,compression=struct.unpack_from('<IIiiHHI',b,10)
    if off!=54 or dib!=40 or planes!=1 or bpp!=24 or compression or not(1<=w<=1920 and 1<=h<=1920):
        raise ValueError('支持54字节头、24位BI_RGB、正高度、1..1920像素BMP；请用工具另存受支持格式')
    expected=54+((w*3+3)//4*4)*h
    if Path(path).stat().st_size!=expected:raise ValueError('BMP长度不符')
    return w,h

def extract_pcm(source,output,duration_s,log=lambda s:None):
    """48k mono s16le, explicitly no track when ffprobe finds no audio."""
    ff=runtime_tools.find('ffmpeg');probe=runtime_tools.find('ffprobe')
    if not ff or not probe:raise RuntimeError('需要FFmpeg与ffprobe来提取音轨')
    p=subprocess.run([probe,'-v','error','-select_streams','a:0','-show_entries','stream=index','-of','json',str(source)],capture_output=True,creationflags=0x08000000)
    if p.returncode:raise ValueError('无法检查输入音轨')
    if not json.loads(p.stdout).get('streams'):log('该视频无音轨；频谱应显示无音轨。');return None
    cmd=[ff,'-nostdin','-v','error','-i',str(source),'-vn','-af','aresample=async=1:first_pts=0,apad','-t',str(duration_s),'-ar','48000','-ac','1','-acodec','pcm_s16le','-f','s16le',str(output)]
    p=subprocess.run(cmd,capture_output=True,creationflags=0x08000000)
    if p.returncode:raise ValueError(p.stderr.decode('utf8','replace')[-1000:])
    # Audio shorter than video is zero padded; longer audio is clipped.
    target=round(duration_s*48000)*2
    with Path(output).open('r+b') as f:f.truncate(target)
    level=pcm_levels(output)
    Path(output).with_suffix('.audio.json').write_text(json.dumps(dict(source=str(source),**level),ensure_ascii=False,indent=2),encoding='utf8')
    if level['all_zero']:log('注意：提取后的音轨全部为0，是静音素材；存在音轨不代表有声音。频谱和波形应为零。')
    elif level['rms_dbfs']<-60:log(f"注意：音轨很轻（RMS {level['rms_dbfs']:.1f} dBFS），不能仅凭播放计数判断声音正常。")
    else:log(f"音轨检查：峰值 {level['peak']}，RMS {level['rms_dbfs']:.1f} dBFS。")
    return Path(output)

def pcm_levels(path):
    """Streaming signed16 LE content check, also valid for an existing PCM."""
    count=peak=nonzero=energy=0
    with Path(path).open('rb') as f:
        for data in iter(lambda:f.read(65536),b''):
            if len(data)%2:raise ValueError('PCM长度必须是2字节的整数倍')
            samples=array.array('h');samples.frombytes(data)
            if sys.byteorder!='little':samples.byteswap()
            count+=len(samples)
            for v in samples:
                peak=max(peak,abs(v));energy+=v*v;nonzero+=v!=0
    if not count:raise ValueError('PCM音轨为空')
    rms=math.sqrt(energy/count)
    return dict(samples=count,peak=peak,rms=rms,rms_dbfs=20*math.log10(rms/32768) if rms else None,nonzero_samples=nonzero,all_zero=not nonzero)

def build(assets,output,voices=(),progress=lambda s:None):
    output=Path(output)
    if output.exists():raise FileExistsError('不覆盖现有镜像，请换文件名')
    if not 1<=len(assets)<=MAX_MEDIA or len(voices) not in (0,4):raise ValueError('媒体1..12项，播报资源须为0或4项')
    all_assets=list(assets)+list(voices);records=[]
    output.parent.mkdir(parents=True,exist_ok=True)
    try:
      with output.open('xb') as f:
        f.truncate(4096*512)
        for i,a in enumerate(all_assets):
          progress(f'封装 {i+1}/{len(all_assets)}：{a.name}')
          payload=Path(a.payload);size=payload.stat().st_size
          f.seek(0,2);start=(f.tell()+16383)//16384*16384;f.seek(start)
          digest=hashlib.sha256();checksum=0
          # Native inner video layout must preserve its relative LBA positions.
          if a.kind==VIDEO:
            import blackbox_studio as old
            h=old.read_header(payload)
            size=(h['bmp_lba']+h['bmp_count']*1801)*512
          with payload.open('rb') as src:
            remaining=size
            while remaining:
              b=src.read(min(1024*1024,remaining))
              if not b:raise ValueError('资源文件截断')
              f.write(b);digest.update(b);checksum=zlib.crc32(b,checksum);remaining-=len(b)
          f.write(bytes((-f.tell())%512));audio_lba=0;samples=0;audio_levels=None
          if a.pcm:
            pcm=Path(a.pcm)
            audio_levels=pcm_levels(pcm)
            if audio_levels['all_zero']:progress(f'注意：{a.name} 音轨全静音，不会产生媒体原声；保留真实静音，不添加假原声。')
            if pcm.stat().st_size%2:raise ValueError('PCM必须是16位单声道整数个样本')
            if a.kind==VOICE and pcm.stat().st_size//2>=1048576:raise ValueError('单句播报须短于21秒')
            audio_lba=f.tell()//512;samples=pcm.stat().st_size//2
            with pcm.open('rb') as src:shutil.copyfileobj(src,f)
            f.write(bytes((-f.tell())%4096))
          b=bytearray(512);b[:8]=ENTRY;b[8]=a.kind;b[9]=bool(samples)
          alias=(a.name.encode('ascii','replace')[:24]);b[10]=len(alias)
          struct.pack_into('<IIIHHHHIIII',b,12,i,start//512,size,a.width,a.height,a.fps,0,a.frames,a.duration_ms,audio_lba,samples)
          struct.pack_into('<I',b,48,checksum&0xffffffff);b[64:64+len(alias)]=alias
          f.seek((i+1)*512);f.write(seal(b));f.seek(0,2)
          records.append(dict(id=i,kind=a.kind,name=a.name,source=a.source,lba=start//512,bytes=size,width=a.width,height=a.height,fps=a.fps,frames=a.frames,duration_ms=a.duration_ms,audio_lba=audio_lba,audio_samples=samples,audio_levels=audio_levels,crc32=f'{checksum&0xffffffff:08x}',sha256=digest.hexdigest()))
        header=bytearray(512);header[:8]=MAGIC
        struct.pack_into('<HHHHII',header,8,1,len(all_assets),len(assets),512,2000,f.tell()//512)
        f.seek(0);f.write(seal(header));f.flush();os.fsync(f.fileno())
      meta=dict(format='ALPHA100',version=1,entries=records,image_bytes=output.stat().st_size,image_sha256=sha(output),sample_rate=48000,pcm='s16le mono',catalog_scan='indexed raw sectors, not FAT32',physical_board_tested=False)
      output.with_suffix('.manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
      output.with_suffix('.sha256').write_text(meta['image_sha256']+'  '+output.name+'\n',encoding='utf8')
      return meta
    except Exception:
      output.unlink(missing_ok=True);raise

def inspect(path,verify_payload=False):
    p=Path(path);size=p.stat().st_size;records=[]
    with p.open('rb') as f:
      head=f.read(512);check(head,MAGIC)
      version,count,visible,record_size,period,sectors=struct.unpack_from('<HHHHII',head,8)
      if version!=1 or not 1<=visible<=12 or not visible<=count<=16 or record_size!=512 or sectors*512!=size:raise ValueError('资源包版本或边界无效')
      for i in range(count):
        f.seek((i+1)*512);b=f.read(512);check(b,ENTRY)
        rid,lba,length,w,h,fps,_,frames,duration,alba,samples=struct.unpack_from('<IIIHHHHIIII',b,12)
        if rid!=i or b[8]>2 or lba<4096 or not length or (lba*512+length)>size or (alba*512+samples*2)>size:raise ValueError('资源越界')
        r=dict(id=i,kind=b[8],name=b[64:64+b[10]].decode('ascii','replace'),lba=lba,bytes=length,width=w,height=h,fps=fps,frames=frames,duration_ms=duration,audio_lba=alba,audio_samples=samples,crc32=struct.unpack_from('<I',b,48)[0])
        if verify_payload:
          f.seek(lba*512);remaining=length;c=0
          while remaining:
            chunk=f.read(min(1024*1024,remaining))
            if not chunk:raise ValueError('资源文件在校验期间被截断')
            c=zlib.crc32(chunk,c);remaining-=len(chunk)
          if c&0xffffffff!=r['crc32']:raise ValueError(f'资源{i} CRC失败')
        records.append(r)
    return dict(version=version,visible=visible,period_ms=period,entries=records,sectors=sectors)
