from pathlib import Path
import subprocess,json,hashlib,re,tempfile,time,datetime,os,shutil

CONFIG=Path(__file__).resolve().parent.parent/'runtime/config.json'
def find_td():
    CONFIG.parent.mkdir(parents=True,exist_ok=True)
    if CONFIG.exists():
        value=json.loads(CONFIG.read_text(encoding='utf-8-sig')).get('td_exe')
        if value:return Path(value).expanduser()
    candidates=[shutil.which('td_commands_prompt.exe'),
                r'C:\Anlogic\TD_6.2.1\bin\td_commands_prompt.exe',
                str(Path(os.environ.get('ProgramFiles',r'C:\Program Files'))/'Anlogic/TD_6.2.1/bin/td_commands_prompt.exe')]
    return next((Path(p) for p in candidates if p and Path(p).is_file()),Path(r'C:\Anlogic\TD_6.2.1\bin\td_commands_prompt.exe'))
TD=find_td()

def configure_td(path):
    global TD
    p=Path(path).absolute()
    if not p.is_file() or p.name.lower()!='td_commands_prompt.exe':raise ValueError('请选择TD安装目录bin内的td_commands_prompt.exe')
    config=json.loads(CONFIG.read_text(encoding='utf-8-sig')) if CONFIG.exists() else {}
    config['td_exe']=str(p);CONFIG.write_text(json.dumps(config,ensure_ascii=False,indent=2),encoding='utf8');TD=p
    return str(p)

class board_access:
    """Keep another tool instance from reconfiguring the FPGA during a transfer."""
    def __enter__(self):
        import ctypes
        from ctypes import wintypes
        self.api=ctypes.WinDLL('kernel32',use_last_error=True)
        self.api.CreateMutexW.argtypes=[ctypes.c_void_p,wintypes.BOOL,wintypes.LPCWSTR];self.api.CreateMutexW.restype=wintypes.HANDLE
        self.api.WaitForSingleObject.argtypes=[wintypes.HANDLE,wintypes.DWORD]
        self.api.ReleaseMutex.argtypes=[wintypes.HANDLE];self.api.CloseHandle.argtypes=[wintypes.HANDLE]
        self.handle=self.api.CreateMutexW(None,False,'Local\\HX4S20C_TF_BOARD_OPERATION')
        if not self.handle:raise ctypes.WinError(ctypes.get_last_error())
        if self.api.WaitForSingleObject(self.handle,0) not in (0,128):
            self.api.CloseHandle(self.handle);self.handle=None
            raise RuntimeError('另一个工具窗口正在操作开发板；本次未开始，避免写卡期间重新下载程序')
        return self
    def __exit__(self,*exc):
        self.api.ReleaseMutex(self.handle);self.api.CloseHandle(self.handle);self.handle=None

def verify_build(project):
    project=Path(project)
    if not (project/'blackbox.bit').is_file():raise ValueError('缺少播放器/维护bit。请先恢复合法依赖并本地重建，或导入有权使用且SHA一致的固件。')
    m=json.loads((project/'verification/build_manifest.json').read_text(encoding='utf-8-sig'))
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
    if sha(project/'blackbox.bit')!=m['bit_sha256'].upper() or m['setup_ns']<0 or m['hold_ns']<0:raise ValueError('固件校验或时序不合格，拒绝下载')
    for rel,h in m['source_sha256'].items():
        if sha(project/rel)!=h.upper():raise ValueError('源码与固件不匹配：'+rel)
    return m

def assert_configuration_log(text,exit_code):
    """TD can return zero despite PRG-9508/9530. Check actual diagnostics."""
    diagnostics='\n'.join(s for s in text.splitlines() if not re.match(r'^\s*RUN-\d+\s*:',s))
    if exit_code or re.search(r'(?i)\b(?:ERROR|FATAL|failed|failure)\b',diagnostics):
        raise RuntimeError('FPGA配置SRAM读回校验失败；下载结束不代表板内配置正确，请展开日志。')
    if not (re.search(r'Chip validation success:\s*EG4S20BG256\b',text) and
            'ReadBack: completed' in text and
            re.search(r'finish command "download -mode x_rdbk\b',text)):
        raise RuntimeError('缺少完整配置SRAM读回校验证据，不能标记通过。')

def verify_configuration_sram(project,log):
    """Configuration cells only, not TF sectors or user ERAM contents.

    Caller must hold board_access and keep the player in its idle browser.
    Reuse the strictly checked ASCII junction
    created by Download-SRAM.ps1; never let the native tool guess a target.
    """
    project=Path(project).absolute();manifest=verify_build(project)
    path_hash=hashlib.sha256(str(project).encode('utf8')).hexdigest().upper()[:12]
    alias=Path(tempfile.gettempdir())/('blackbox_phase3_'+path_hash)
    if not alias.exists() or alias.resolve()!=project.resolve():
        raise RuntimeError('未找到指向当前工程的已验证下载路径，未执行配置校验。')
    log('读取FPGA配置SRAM并与所选bit比较；不读写TF卡，不写启动Flash。')
    with tempfile.TemporaryDirectory(prefix='alpha_cfgverify_') as temp:
        tcl=Path(temp)/'verify.tcl'
        tcl.write_text('download -mode x_rdbk -bit {'+(alias/'blackbox.bit').as_posix()+'} -cable 0 -spd 6 -error_max 1 -v\nexit\n',encoding='ascii')
        p=subprocess.run([str(TD),tcl.as_posix()],stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60,creationflags=0x08000000)
    text=p.stdout.decode('utf8',errors='replace')
    (project/'download_configuration_latest.log').write_text(text,encoding='utf8')
    for s in text.splitlines():log(s)
    assert_configuration_log(text,p.returncode)
    return dict(status='CONFIGURATION_SRAM_VERIFIED',bit_sha256=manifest['bit_sha256'],user_ERAM_verified=False,TF_verified=False)

def download(project,log,diagnostic=False,verify_configuration=False,expected_runtime=None,device=None):
    project=Path(project);verify_build(project)
    if (project/'BOARD_TEST_REJECTED.json').exists() and not diagnostic:
        raise RuntimeError('该候选未通过实板启动验证，已停用默认下载；请使用工作台中的ART9回退版本。')
    if not TD.is_file():raise RuntimeError('找不到安路TD；请在工作台“TD工具路径”选择安装目录bin内的td_commands_prompt.exe')
    cmd=['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(project/'Download-SRAM.ps1'),'-TDExe',str(TD)]
    if diagnostic:cmd.append('-AllowBoardDiagnostic')
    process=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,creationflags=0x08000000)
    lines=[]
    for b in iter(process.stdout.readline,b''):
        try:s=b.decode('utf-8').rstrip()
        except UnicodeDecodeError:s=b.decode('gb18030','replace').rstrip()
        lines.append(s);log(s)
    code=process.wait();process.stdout.close()
    if code or not any('PASS: TD returned exit code 0' in s for s in lines):raise RuntimeError('TD未确认下载成功，请展开日志')
    result=dict(status='SRAM_PROGRAMMED',bit_sha256=verify_build(project)['bit_sha256'])
    if verify_configuration:
        if not device:raise RuntimeError('候选配置校验需要实际播放器串口，未猜测设备端口。')
        before=monitor_alpha(device,timeout=12,expected_runtime=expected_runtime)
        if not before['catalog_ready'] or before['error'] or not before['browser'] or before.get('catalog_busy'):
            raise RuntimeError('候选未处于就绪资源库，未在播放或读卡途中执行配置回读。')
        result['configuration']=verify_configuration_sram(project,log)
        after=monitor_alpha(device,timeout=12,expected_runtime=expected_runtime)
        if not after['catalog_ready'] or after['error'] or not after['browser']:
            raise RuntimeError('配置校验结束后播放器未恢复就绪资源库，不能标记恢复成功。')
        result['runtime']=after
    return result

def monitor_playback(device,timeout=12,log=None):
    """Observe real player telemetry; this does not verify a physical HDMI picture."""
    import serial,protocol
    if device not in [p.device for p in protocol.list_devices()]:raise RuntimeError('播放程序已下载，但未找到对应CH340，尚未验证恢复播放')
    samples=[];buf=bytearray();deadline=time.monotonic()+timeout
    with serial.Serial(device,115200,timeout=.1,write_timeout=1) as port:
      while time.monotonic()<deadline:
        buf.extend(port.read(max(1,port.in_waiting)))
        while True:
          n=buf.find(b'BBSTAT05')
          if n<0:
            if len(buf)>7:del buf[:-7]
            break
          if n:del buf[:n]
          if len(buf)<80:break
          f=bytes(buf[:80]);del buf[:80]
          samples.append(dict(frame_id=int.from_bytes(f[8:12],'little'),flags=f[22],crc_ok=bool(f[22]&16),error=f[25],cache_ready=int.from_bytes(f[26:28],'little'),raw=f.hex()))
          recent=samples[-6:]
          if len(recent)==6 and len({s['frame_id'] for s in recent})>=2 and all(s['error']==0 and s['crc_ok'] and s['cache_ready']>0 for s in recent):
            result=dict(status='PLAYER_TELEMETRY_PASS',utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),port=device,samples=recent,frame_advancing=True,crc_ok=True,hdmi_visual_verified=False)
            if log:log('播放状态验证通过：帧号递增、CRC正常、错误0。HDMI实看需另行验证。')
            return result
    raise RuntimeError('播放程序已下载，但未观察到连续正常的播放状态；不能标记恢复成功。'+('最近状态：'+str(samples[-1]) if samples else '没有BBSTAT05应答。'))

def monitor_alpha(device,timeout=8,log=None,expected_runtime=None):
    import serial,protocol,alpha_link
    if device not in [p.device for p in protocol.list_devices()]:raise RuntimeError('未找到CH340，固件下载状态与媒体状态不能混为一谈')
    last=None;unexpected=None
    with serial.Serial(device,115200,timeout=.1) as port:
      # Discard bytes from the program replaced by this download. A valid
      # old packet is not evidence that the requested candidate has started.
      port.reset_input_buffer()
      for last in alpha_link.read_status(port,timeout):
        if expected_runtime is not None and last.get('runtime_tag')!=expected_runtime:
          unexpected=last;last=None;continue
        if last['catalog_ready'] or last['error']:
          if log:log('收到真实Alpha状态：'+str(last))
          return last
    if last:return last
    if unexpected is not None:
      raise RuntimeError('期望固件 '+expected_runtime+'，实际应答为 '+str(unexpected.get('runtime_tag','未知'))+'；未确认本次候选启动，不能标记恢复成功。')
    raise RuntimeError('未收到带CRC的Alpha状态，不能将下载成功当作播放器就绪')

def restart_serial(device,log):
    """Restart only the selected CH340 PnP device; never a USB hub or disk."""
    if not re.fullmatch(r'COM[0-9]+',device):raise ValueError('串口名称无效')
    script="$ErrorActionPreference='Stop'; Get-PnpDevice -Class Ports -PresentOnly | Where-Object {$_.InstanceId -like 'USB\\VID_1A86&PID_7523*' -and $_.FriendlyName.EndsWith('("+device+")')} | Select-Object -ExpandProperty InstanceId"
    p=subprocess.run(['powershell.exe','-NoProfile','-Command',script],capture_output=True,creationflags=0x08000000)
    lines=p.stdout.decode('utf-8','replace').strip().splitlines()
    ids=[x.strip() for x in lines if re.fullmatch(r'USB\\VID_1A86&PID_7523[^\r\n\x27]*',x.strip(),re.I)]
    if p.returncode or len(ids)!=1:raise RuntimeError('无法唯一定位所选CH340设备；未重启任何硬件')
    with tempfile.TemporaryDirectory(prefix='hxtf_serial_') as temp:
      folder=Path(temp);result=folder/'result.txt';code=folder/'restart.ps1'
      code.write_text("$ErrorActionPreference='Stop'\n& pnputil.exe /restart-device '"+ids[0]+"' *> '"+str(result)+"'\nexit $LASTEXITCODE\n",encoding='utf-8-sig')
      # UAC is handled by Windows; refusal is reported, not bypassed.
      outer="$p=Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','\""+str(code)+"\"') -Verb RunAs -WindowStyle Hidden -PassThru -Wait; exit $p.ExitCode"
      log('重启所选CH340设备。Windows可能显示系统管理员确认；不会重启USB集线器，也不访问磁盘。')
      p=subprocess.run(['powershell.exe','-NoProfile','-Command',outer],capture_output=True,creationflags=0x08000000)
      if result.exists():log(result.read_text(encoding='utf-16',errors='replace'))
      if p.returncode:raise RuntimeError('CH340重启未完成，可能未允许Windows管理员操作；请查看日志')
    return '所选CH340已重启，请重新连接设备；尚未写卡。'
