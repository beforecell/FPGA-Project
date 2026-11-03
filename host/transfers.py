"""Confirmed board-sector operations with complete read-back verification."""
from pathlib import Path
import hashlib,json,time,os

HEADER_LBA=2337

def wire_seconds(sectors,write_and_verify=True):
    # 1 Mbaud, 8N1: 100000 bytes/s. Request+response are 596 bytes per sector
    # for either WRITE (532+64) or READ (20+576). SD/USB/host waits add time.
    return sectors*596*(2 if write_and_verify else 1)/100000

def sha256_file(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()

def image_details(path):
    p=Path(path)
    if p.suffix.lower()!='.img' or not p.is_file():raise ValueError('请选择已有.img镜像，不可直接发送MP4')
    size=p.stat().st_size
    if size==0 or size%512:raise ValueError('镜像大小必须是512字节的整数倍')
    if size//512>0xffffffff:raise ValueError('镜像超过本协议扇区数上限')
    with p.open('rb') as f:
        first=f.read(8);f.seek(HEADER_LBA*512);magic=f.read(8)
    fmt='UNKNOWN';commit=None
    if first==b'ALPHA100':
        import alpha_package
        alpha_package.inspect(p);fmt='ALPHA100';commit=0
    elif magic==b'HXBBX005':fmt='HXBBX005';commit=HEADER_LBA
    return dict(path=str(p.absolute()),bytes=size,sectors=size//512,sha256=sha256_file(p),compatible=fmt!='UNKNOWN',format=fmt,commit_lba=commit)

def write_image(client,path,confirmed_card,details,cancel,progress=None,record=None):
    """Caller must display identity/range and obtain explicit confirmation first."""
    p=Path(path);progress=progress or (lambda **kw:None);start=time.monotonic()
    retry_before=client.retry_count;corrupt_before=getattr(client,'rx_corrupt_frames',0)
    result=dict(operation='write_image',status='INCOMPLETE',source=str(p),source_sha256=details['sha256'],
                card_cid=confirmed_card.identity,card_sectors=confirmed_card.sectors,
                start_lba=0,sectors=details['sectors'],acknowledged_sectors=0,verified_bytes=0,
                transport=getattr(client,'channel','uart'),window=getattr(client,'window',1))
    def save():
        if record:Path(record).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    def checkpoint():
        if cancel.is_set():raise InterruptedError('已取消；镜像未完成或未通过完整校验，不能显示成功')
    try:
        checkpoint()
        current=client.info()
        if current.cid!=confirmed_card.cid or current.sectors!=confirmed_card.sectors or not current.initialized:raise ValueError('目标卡身份或状态已变化，请重新连接并确认')
        if p.stat().st_size!=details['bytes'] or sha256_file(p)!=details['sha256']:raise ValueError('镜像文件已变化，请重新选择')
        client.arm(current,0,details['sectors']);save()
        commit=details.get('commit_lba',HEADER_LBA if details['compatible'] else None)
        if commit is not None:
            client.write_sector(commit,bytes(512));result['header_invalidated']=True;save()
        batch_size=32 if hasattr(client,'write_sectors') else 1
        with p.open('rb') as f:
            batch=[];batch_lba=0
            for lba in range(details['sectors']):
                checkpoint();data=f.read(512)
                if len(data)!=512:raise ValueError('镜像在传输时被截断')
                if lba==commit:continue
                if not batch:batch_lba=lba
                batch.append(data)
                if len(batch)==batch_size or lba+1==details['sectors'] or lba+1==commit:
                    if batch_size>1:client.write_sectors(batch_lba,batch,cancel=cancel)
                    else:client.write_sector(batch_lba,batch[0])
                    result['acknowledged_sectors']+=len(batch);batch=[]
                    progress(phase='写入',done=result['acknowledged_sectors']*512,total=details['bytes'],started=start,
                             overall_done=result['acknowledged_sectors']*512,overall_total=details['bytes']*2,overall_started=start)
            checkpoint()
            if commit is not None:
                f.seek(commit*512);client.write_sector(commit,f.read(512));result['acknowledged_sectors']+=1;result['header_committed']=True
        progress(phase='写入',done=details['bytes'],total=details['bytes'],started=start,
                 overall_done=details['bytes'],overall_total=details['bytes']*2,overall_started=start)
        result['write_elapsed_s']=time.monotonic()-start
        save();checkpoint()
        if sha256_file(p)!=details['sha256']:raise ValueError('源镜像在写入期间发生变化')
        h=hashlib.sha256();verify_start=time.monotonic()
        with p.open('rb') as f:
            for lba in range(0,details['sectors'],batch_size):
                checkpoint();count=min(batch_size,details['sectors']-lba)
                blocks=client.read_sectors(lba,count,cancel=cancel) if batch_size>1 else [client.read_sector(lba)]
                for offset,actual in enumerate(blocks):
                    expected=f.read(512)
                    if actual!=expected:raise ValueError(f'读回与源镜像不同：LBA {lba+offset}')
                    h.update(actual);result['verified_bytes']+=512
                progress(phase='读回校验',done=result['verified_bytes'],total=details['bytes'],started=verify_start,
                         overall_done=details['bytes']+result['verified_bytes'],overall_total=details['bytes']*2,overall_started=start)
        result['readback_elapsed_s']=time.monotonic()-verify_start
        result['readback_sha256']=h.hexdigest()
        if h.hexdigest()!=details['sha256']:raise ValueError('完整SHA256不一致')
        checkpoint();client.disarm()
        result.update(status='VERIFIED',elapsed_s=time.monotonic()-start,retries=client.retry_count-retry_before,
                      rx_corrupt_frames=getattr(client,'rx_corrupt_frames',0)-corrupt_before)
        save();return result
    except Exception as e:
        result.update(status='CANCELLED_INCOMPLETE' if isinstance(e,InterruptedError) else 'FAILED_INCOMPLETE',error=str(e),elapsed_s=time.monotonic()-start)
        save()
        try:client.disarm()
        except Exception:pass
        raise

def export_range(client,path,start_lba,count,card,cancel,progress=None):
    if start_lba<0 or count<=0 or start_lba+count>card.sectors:raise ValueError('读取范围超出卡容量')
    p=Path(path);partial=p.with_name(p.name+'.partial')
    if p.exists() or partial.exists():raise FileExistsError('导出目标或.partial文件已存在，请换一个文件名')
    h=hashlib.sha256();begin=time.monotonic()
    with partial.open('xb') as f:
        batch_size=32 if hasattr(client,'read_sectors') else 1
        for n in range(0,count,batch_size):
            if cancel.is_set():raise InterruptedError('导出已取消，保留.partial文件；不是完整镜像')
            number=min(batch_size,count-n)
            b=b''.join(client.read_sectors(start_lba+n,number,cancel=cancel)) if batch_size>1 else client.read_sector(start_lba+n)
            if len(b)!=number*512:raise ValueError('导出读取长度不符，保留未完成文件')
            f.write(b);h.update(b)
            if progress:progress(phase='导出',done=(n+number)*512,total=count*512,started=begin)
        f.flush();os.fsync(f.fileno())
    if cancel.is_set():raise InterruptedError('导出已取消，保留.partial文件')
    partial.rename(p)
    result=dict(status='EXPORTED',card_cid=card.identity,start_lba=start_lba,sectors=count,bytes=count*512,sha256=h.hexdigest())
    p.with_suffix(p.suffix+'.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    return result
