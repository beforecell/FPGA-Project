"""Offline reproduction regressions for both delivery layouts.No board I/O."""
from pathlib import Path
import sys,os,argparse,json,tempfile,subprocess,io,importlib.util,shutil
from unittest.mock import patch,Mock
parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path);args=parser.parse_args()
if args.root:R=args.root.resolve()
else:
 R=next(p for p in Path(__file__).resolve().parents if (p/'README.md').exists() or (p/'00_先看这里.html').exists())
PUBLIC=(R/'host').is_dir();H=R/('host' if PUBLIC else '02_上位机源码');T=R/('scripts' if PUBLIC else '03_构建与复现')
V=R/('verification' if PUBLIC else '05_验证资料/版本与证据')
sys.path[:0]=[str(H),str(T)]
import device_tools,project_paths,alpha_studio,protocol,network_transport
spec=importlib.util.spec_from_file_location('repro_source_verifier',T/'verify_sources.py');verifier=importlib.util.module_from_spec(spec);spec.loader.exec_module(verifier)
results=[]
def case(name,f):
 try:f();results.append(dict(test=name,status='PASS'));print('PASS',name,flush=True)
 except Exception as e:results.append(dict(test=name,status='FAIL',error=repr(e)));print('FAIL',name,repr(e),flush=True)
def missing_project():
 with tempfile.TemporaryDirectory(prefix='alpha_missing_project_') as tmp:
  tmp=Path(tmp)
  if PUBLIC:
   (tmp/'fpga').mkdir();(tmp/'verification').mkdir();shutil.copy2(V/'versions.json',tmp/'verification/versions.json')
  else:(tmp/'05_验证资料/版本与证据').mkdir(parents=True);shutil.copy2(V/'versions.json',tmp/'05_验证资料/版本与证据/versions.json')
  with patch.object(verifier,'R',tmp):
   try:verifier.verify(False)
   except (FileNotFoundError,ValueError):return
   raise AssertionError('Missing all4 FPGA project directories was incorrectly accepted')
case('missing_entire_FPGA_project_must_fail',missing_project)
def download_model(marker,want_flag):
 with tempfile.TemporaryDirectory(prefix='alpha_download_args_') as tmp:
  tmp=Path(tmp);td=tmp/'td_commands_prompt.exe';td.write_bytes(b'not-executed')
  if marker:(tmp/'BOARD_TEST_REJECTED.json').write_text('{}')
  (tmp/'Download-SRAM.ps1').write_text('param([string]$TDExe'+(',[switch]$AllowBoardDiagnostic' if marker else '')+')')
  proc=Mock();proc.stdout=io.BytesIO(b'PASS: TD returned exit code 0\n');proc.wait.return_value=0
  with patch.object(device_tools,'TD',td),patch.object(device_tools,'verify_build',return_value=dict(bit_sha256='A'*64)),patch.object(device_tools.subprocess,'Popen',return_value=proc) as popen:
   device_tools.download(tmp,lambda _:None,diagnostic=True)
   has_flag='-AllowBoardDiagnostic' in popen.call_args.args[0]
   assert has_flag==want_flag,('unexpected diagnostic argument',popen.call_args.args[0])
case('registered_network_firmware_no_player_only_argument',lambda:download_model(False,False))
case('diagnostic_player_keeps_required_explicit_argument',lambda:download_model(True,True))
def installer_failure_exit():
 with tempfile.TemporaryDirectory(prefix='alpha_cmd_exit_') as tmp:
  tmp=Path(tmp);folder=tmp/('scripts' if PUBLIC else '03_构建与复现');folder.mkdir()
  (folder/'Install.ps1').write_text("throw 'intentional offline installer failure fixture'",encoding='utf-8-sig')
  shutil.copy2(R/'安装环境.cmd',tmp/'安装环境.cmd')
  p=subprocess.run([os.environ['COMSPEC'],'/d','/c',str(tmp/'安装环境.cmd')],cwd=tmp,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,creationflags=0x08000000)
  assert p.returncode!=0,'CMD pause masked failed PowerShell installation as exit0'
case('installer_CMD_propagates_PowerShell_failure',installer_failure_exit)
def VBS_check_mode():
 with tempfile.TemporaryDirectory(prefix='alpha_vbs_check_') as tmp:
  tmp=Path(tmp);bindir=tmp/'.venv/Scripts';bindir.mkdir(parents=True)
  # Invalid executables detect any unintended launch:--check must only print.
  (bindir/'pythonw.exe').write_bytes(b'invalid executable must not run')
  (tmp/('host' if PUBLIC else '02_上位机源码')).mkdir()
  (tmp/('host' if PUBLIC else '02_上位机源码')/'launch_alpha.py').write_text('raise RuntimeError("must not run")')
  shutil.copy2(R/'启动工作台.vbs',tmp/'启动工作台.vbs')
  p=subprocess.run(['cscript.exe','//Nologo',str(tmp/'启动工作台.vbs'),'--check'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,creationflags=0x08000000)
  assert p.returncode==0 and b'pythonw.exe' in p.stdout,'--check tried to launch GUI or did not resolve interpreter'
case('VBS_check_does_not_launch_GUI',VBS_check_mode)
def dependency_check_noninteractive():
 import tkinter as check_tk
 spec=importlib.util.spec_from_file_location('repro_launch_alpha',H/'launch_alpha.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 with patch.object(sys,'argv',['launch_alpha.py','--check']),patch.object(module.importlib,'import_module',side_effect=ImportError('intentional missing dependency')),patch.object(check_tk,'Tk',side_effect=AssertionError('CLI check must not open a modal')),patch.object(sys,'stderr',io.StringIO()):
  assert module.main()==1
case('missing_dependency_CLI_check_returns_error_without_modal',dependency_check_noninteractive)
import tkinter as tk
from tkinter import messagebox
from PIL import Image
def oversized_image_rejected_early():
 with tempfile.TemporaryDirectory(prefix='alpha_image_bounds_') as tmp:
  path=Path(tmp)/'wide.png';Image.new('RGB',(2000,10),'blue').save(path)
  with patch.object(protocol,'list_devices',return_value=[]),patch.object(network_transport,'list_adapters',return_value=[]),patch.object(messagebox,'showerror') as error:
   root=tk.Tk();root.withdraw();app=alpha_studio.AlphaApp(root)
   try:app._add('image',path);assert not app.assets and error.called,'Oversize image accepted until after potentially expensive video encoding'
   finally:app.close()
case('image_dimensions_validated_before_batch_encoding',oversized_image_rejected_early)
def network_status_label():
 with patch.object(protocol,'list_devices',return_value=[]),patch.object(network_transport,'list_adapters',return_value=[]):
  root=tk.Tk();root.withdraw();app=alpha_studio.AlphaApp(root)
  try:
   app.client=Mock(channel='ethernet');app.set_card=Mock();app.q.put(('card',object()));app.poll()
   label=app.connection.get();assert '网口' in label and 'CH340' not in label,label
  finally:app.client=None;app.close()
case('network_write_card_refresh_keeps_ethernet_label',network_status_label)
def sample_description():
 with patch.object(protocol,'list_devices',return_value=[]),patch.object(network_transport,'list_adapters',return_value=[]),patch.object(alpha_studio.package,'inspect',return_value=dict(visible=5 if PUBLIC else 3)):
  root=tk.Tk();root.withdraw();app=alpha_studio.AlphaApp(root)
  try:
   app.select_demo();label=app.result.get()
   if PUBLIC:assert '合成' in label and '实测' not in label and '夜间' not in label,label
   else:assert '夜间' in label and '两张' in label,label
  finally:app.close()
case('selected_demo_description_matches_distribution',sample_description)
def existing_IMG_rejected_before_work():
 from tkinter import filedialog
 with tempfile.TemporaryDirectory(prefix='alpha_existing_IMG_') as tmp:
  tmp=Path(tmp);image=tmp/'photo.bmp';Image.new('RGB',(32,32),'red').save(image)
  output=tmp/'existing.img';output.write_bytes(b'preserve me')
  with patch.object(protocol,'list_devices',return_value=[]),patch.object(network_transport,'list_adapters',return_value=[]),patch.object(messagebox,'showerror') as error,patch.object(filedialog,'asksaveasfilename',return_value=str(output)):
   root=tk.Tk();root.withdraw();app=alpha_studio.AlphaApp(root)
   try:
    app._add('image',image);app.run=Mock(side_effect=AssertionError('Must not start encoding'))
    app.make_package();assert error.called and not app.run.called and output.read_bytes()==b'preserve me'
   finally:app.close()
case('existing_output_detected_before_encoding_and_not_overwritten',existing_IMG_rejected_before_work)
def build_wrapper_without_GetFileHash():
 import hashlib
 with tempfile.TemporaryDirectory(prefix='alpha_build_wrapper_') as tmp:
  tmp=Path(tmp);scripts=tmp/('scripts' if PUBLIC else '03_构建与复现');scripts.mkdir()
  metadata=tmp/('verification' if PUBLIC else '05_验证资料/版本与证据');metadata.mkdir(parents=True)
  versions=json.loads((V/'versions.json').read_text(encoding='utf8'));(metadata/'versions.json').write_text(json.dumps(versions),encoding='utf8')
  project=tmp/versions['player']['project_relative'];(project/'verification').mkdir(parents=True)
  (project/'tiny.v').write_text('module tiny;endmodule')
  manifest=dict(source_sha256={'tiny.v':hashlib.sha256((project/'tiny.v').read_bytes()).hexdigest()})
  (project/'verification/build_manifest.json').write_text(json.dumps(manifest),encoding='utf8')
  (project/'Build.ps1').write_text('param([string]$TDExe)\nSet-Content -LiteralPath (Join-Path $PSScriptRoot "fixture_completed.txt") -Value "No native tool invoked"\nexit 0\n')
  (project/'Download-SRAM.ps1').write_text('throw "must not download"')
  shutil.copy2(T/'Build.ps1',scripts/'Build.ps1');td=tmp/'td_commands_prompt.exe';td.write_bytes(b'invalid;must not run')
  # Shadow the cmdlet to make an accidental dependency fail on every machine.
  script="function Get-FileHash { throw 'Get-FileHash must not be required' }; & '"+str(scripts/'Build.ps1').replace("'","''")+"' -Project player -TDExe '"+str(td).replace("'","''")+"'"
  p=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-Command',script],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,creationflags=0x08000000)
  assert p.returncode==0,p.stdout.decode('utf8',errors='replace')
  assert len(list(tmp.rglob('fixture_completed.txt')))==1,'Copied source Build.ps1 was not reached'
case('Build_wrapper_stages_valid_sources_without_GetFileHash',build_wrapper_without_GetFileHash)
def image_copy_helper():
 import hashlib,struct
 with tempfile.TemporaryDirectory(prefix='alpha_image_prepare_') as tmp:
  tmp=Path(tmp);source=tmp/'原图';source.mkdir();original=source/'超宽图片.png';Image.new('RGB',(2400,1000),'red').save(original)
  before=hashlib.sha256(original.read_bytes()).digest();output=tmp/'板端副本'
  p=subprocess.run([sys.executable,'-X','utf8',str(T/'prepare_images.py'),str(source),'--output',str(output)],capture_output=True,text=True,encoding='utf8',creationflags=0x08000000)
  assert p.returncode==0,p.stdout+p.stderr
  data=(output/'IMAGE01.bmp').read_bytes();assert struct.unpack_from('<ii',data,18)==(640,480) and struct.unpack_from('<H',data,28)[0]==24
  assert hashlib.sha256(original.read_bytes()).digest()==before
  p=subprocess.run([sys.executable,'-X','utf8',str(T/'prepare_images.py'),str(source),'--output',str(output)],capture_output=True,creationflags=0x08000000)
  assert p.returncode!=0 and (output/'IMAGE01.bmp').read_bytes()==data,'Existing output was overwritten'
case('image_copy_640x480_no_original_or_existing_output_overwrite',image_copy_helper)
def GUI_eight_asset_batch():
 import alpha_package,media_pipeline
 from tkinter import filedialog
 ffmpeg=media_pipeline.runtime_tools.find('ffmpeg');assert ffmpeg,'FFmpeg is required for this end-to-end software test'
 with tempfile.TemporaryDirectory(prefix='alpha_GUI_batch_') as tmp:
  tmp=Path(tmp)/'中文素材 带空格';tmp.mkdir()
  video=tmp/'原声视频.mp4'
  command=[ffmpeg,'-nostdin','-v','error','-f','lavfi','-i','testsrc=size=160x120:rate=60','-f','lavfi','-i','sine=frequency=750:sample_rate=48000','-t','0.2','-c:v','mpeg4','-c:a','aac','-pix_fmt','yuv420p',str(video)]
  subprocess.run(command,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=0x08000000)
  silent=tmp/'无音轨视频.mp4'
  subprocess.run([ffmpeg,'-nostdin','-v','error','-i',str(video),'-an','-c:v','copy',str(silent)],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=0x08000000)
  images=[]
  for i,size in enumerate([(640,480),(1920,1080),(360,640),(480,480),(1280,720),(640,480)]):
   p=tmp/f'图片{i}.png';Image.new('RGB',size,(20+i*20,70,100)).save(p);images.append(p)
  output=tmp/'完整资源包.img'
  with patch.object(protocol,'list_devices',return_value=[]),patch.object(network_transport,'list_adapters',return_value=[]),patch.object(device_tools,'download',side_effect=AssertionError('No board download in media preparation')),patch.object(filedialog,'asksaveasfilename',return_value=str(output)):
   root=tk.Tk();root.withdraw();app=alpha_studio.AlphaApp(root)
   try:
    for p in [video,silent]:app._add('video',p)
    for p in images:app._add('image',p)
    assert len(app.assets)==8
    app.fps.set('30');app.seconds.set('0');app.quality.set('balanced')
    def run(work,*a,**kw):
     assert kw.get('needs_board') is False,'Encoding acquired a board operation'
     return work()
    app.run=run;app.make_package();app.poll()
    assert app.img.get()==str(output),'GUI did not select the complete container output'
    meta=alpha_package.inspect(output,True);assert meta['visible']==8
    kinds=[x['kind'] for x in meta['entries']];assert kinds.count(alpha_package.VIDEO)==2 and kinds.count(alpha_package.IMAGE)==6
    assert set(kinds).issubset({0,1,2})
    entries=meta['entries'];assert entries[0]['audio_samples']>0 and entries[1]['audio_samples']==0
    manifest=json.loads(output.with_suffix('.manifest.json').read_text(encoding='utf8'))
    assert manifest['entries'][0]['audio_levels']['nonzero_samples']>0
    assert all(x['fps']==30 for x in entries if x['kind']==alpha_package.VIDEO)
   finally:app.close()
case('actual_GUI_2video6image_Unicode_batch_audio_and_complete_IMG',GUI_eight_asset_batch)
if PUBLIC:
 def download_bad_SHA():
  spec=importlib.util.spec_from_file_location('repro_release_download',T/'download_release.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  with tempfile.TemporaryDirectory(prefix='alpha_bad_download_') as tmp:
   tmp=Path(tmp);(tmp/'verification').mkdir();shutil.copy2(V/'versions.json',tmp/'verification/versions.json');versions=json.loads((V/'versions.json').read_text(encoding='utf8'))
   assets=[dict(name=f'{role}-{m["bit_sha256"][:12]}.bit',digest='sha256:'+m['bit_sha256'].lower(),size=7,browser_download_url='https://github.com/test/'+role) for role,m in versions.items()]
   responses=[io.BytesIO(json.dumps(dict(draft=False,assets=assets)).encode()),io.BytesIO(b'corrupt')]
   with patch.object(module,'R',tmp),patch.object(sys,'argv',['download_release.py']),patch.object(module.urllib.request,'urlopen',side_effect=responses):
    try:module.download()
    except SystemExit as e:assert 'SHA256' in str(e)
    else:raise AssertionError('Corrupt release download accepted')
   assert not list(tmp.rglob('*.bit')),'Unverified firmware was imported'
 case('public_release_wrong_SHA_never_imports_firmware',download_bad_SHA)
output=R/('runtime' if PUBLIC else '运行记录')/'tests/reproduction_regression.json';output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(dict(status='PASS' if all(x['status']=='PASS' for x in results) else 'FAIL',scope='Offline integration/argument/error/GUI models;no board access',tests=results),ensure_ascii=False,indent=2),encoding='utf8')
if any(x['status']=='FAIL' for x in results):raise SystemExit(1)
