"""Offline repository checks.No device/network-setting/Flash/card actions."""
from pathlib import Path
import sys,json,tempfile,subprocess,struct,zlib,hashlib,importlib.util,shutil
from unittest.mock import patch
R=Path(__file__).resolve().parents[1];sys.path[:0]=[str(R/'host'),str(R/'scripts')]
import alpha_studio,alpha_link,alpha_package,device_tools,network_transport,protocol,media_pipeline,project_paths
from verify_sources import verify
from solidify_flash import check_log
from PIL import Image
results=[]
results.append(dict(test='235_frozen_inputs',projects=verify(False),status='PASS'))
for role in ('player','tf-maintenance','uart-maintenance','fallback-art9'):
 P=R/project_paths.relative(role)
 if (P/'blackbox.bit').exists():device_tools.verify_build(P);results.append(dict(test='exact_bit_binding',role=role,status='PASS'))
with tempfile.TemporaryDirectory(prefix='public_alpha_') as t:
 t=Path(t);bmp=t/'own.bmp';Image.new('RGB',(640,480),'#246789').save(bmp)
 out=t/'own.img';alpha_package.build([alpha_package.Asset(alpha_package.IMAGE,'OWN_TEST',bmp,640,480)],out)
 assert alpha_package.inspect(out,True)['visible']==1;results.append(dict(test='new_640x480_BMP_package',status='PASS'))
 ff=media_pipeline.runtime_tools.find('ffmpeg');probe=media_pipeline.runtime_tools.find('ffprobe')
 assert ff and probe,'Install ffmpeg and ffprobe to run the MP4 test'
 mp4=t/'own.mp4';subprocess.run([ff,'-nostdin','-v','error','-f','lavfi','-i','testsrc=size=160x120:rate=25','-f','lavfi','-i','sine=frequency=750:sample_rate=48000','-t','0.16','-pix_fmt','yuv420p','-c:v','mpeg4','-c:a','aac',str(mp4)],check=True,creationflags=0x08000000)
 frames=list(media_pipeline.frames(mp4,25,max_frames=4));assert len(frames)==4
 pcm=alpha_package.extract_pcm(mp4,t/'pcm.pcm',.16);levels=alpha_package.pcm_levels(pcm);assert levels['nonzero_samples']>0
 import blackbox_studio
 inner=t/'video.img';blackbox_studio.make_image(iter(frames),inner,fps=25,quality='balanced')
 alpha_package.build([alpha_package.Asset(alpha_package.VIDEO,'TEST',inner,640,480,25,4,160,pcm)],t/'full.img');assert alpha_package.inspect(t/'full.img',True)['visible']==1
 results.append(dict(test='MP4_4frames_nonzero_PCM_complete_Alpha',samples=levels['samples'],status='PASS'))
import tkinter as tk
with patch.object(device_tools,'download',side_effect=AssertionError('No hardware programming in tests')),patch.object(protocol,'list_devices',return_value=[]),patch.object(network_transport,'list_adapters',return_value=[]):
 root=tk.Tk();root.withdraw();app=alpha_studio.AlphaApp(root);root.update_idletasks();assert app.playback_variant.get().startswith('ARTF');assert alpha_studio.load_voices()==[];app.close()
results.append(dict(test='actual_Tk_GUI_without_optional_voices',status='PASS'))
raw=bytearray.fromhex((R/'tests/status_fixture.hex').read_text().strip());raw[60:64]=b'ARTF';raw[-4:]=struct.pack('<I',zlib.crc32(raw[:-4])&0xffffffff)
state=alpha_link.StatusDecoder().feed(raw)[0];assert state['runtime_tag']=='ARTF' and not state['fft_enabled']
base=dict(state,browser=False,loading=False,seek_busy=False,announcing=False,image_mode=False,analysis_on=False,fullscreen=True,keyframe_mode=False,adjust_mode=False,speed_mode=False)
assert '上一帧' in alpha_studio.player_controls(base)[1]['up']
assert '上一视图' in alpha_studio.player_controls(dict(base,analysis_on=True))[1]['hold3']
assert '轮播' in alpha_studio.player_controls(dict(base,image_mode=True))[1]['hold2']
results.append(dict(test='ARTF_context_control_labels',status='PASS'))
check_log((R/'verification/evidence/bw-program-verify-redacted.txt').read_text(encoding='utf8'),0)
for text,code in [('PRG-9508 ERROR: mismatch',0),('invalid command name "program_spi"',0),('',0),('',1)]:
 try:check_log(text,code)
 except RuntimeError:pass
 else:raise AssertionError('Invalid Flash log accepted')
source=(R/'scripts/solidify_flash.py').read_text();assert '-error_max' not in source
results.append(dict(test='BW_failure_log_rejection_and_argument_set',status='PASS'))
if (R/'fpga/player/blackbox.bit').is_file():
 with tempfile.TemporaryDirectory(prefix='alpha_local_profile_') as tmp:
  t=Path(tmp)
  for name in ['host','verification']:
   shutil.copytree(R/name,t/name,ignore=shutil.ignore_patterns('__pycache__'))
  (t/'scripts').mkdir();shutil.copy2(R/'scripts/register_build.py',t/'scripts/register_build.py')
  shutil.copytree(R/'fpga/player',t/'fpga/player')
  before=hashlib.sha256((t/'fpga/player/verification/build_manifest.json').read_bytes()).hexdigest()
  p=subprocess.run([sys.executable,'-X','utf8',str(t/'scripts/register_build.py'),'player',str(t/'fpga/player')],capture_output=True,text=True,encoding='utf8',creationflags=0x08000000)
  assert p.returncode==0,p.stdout+p.stderr
  local=json.loads((t/'runtime/local-firmware.json').read_text(encoding='utf8'))['player']
  assert local['local_build'] and local['diagnostic_only'] and not local['board_verified']
  assert local['project_relative'].startswith('runtime/firmware/')
  assert hashlib.sha256((t/'fpga/player/verification/build_manifest.json').read_bytes()).hexdigest()==before
 results.append(dict(test='local_registration_preserves_frozen_manifest_and_diagnostic_scope',status='PASS'))
 with tempfile.TemporaryDirectory(prefix='alpha_flash_dry_') as tmp:
  exe=Path(tmp)/'bw_commands_prompt.exe';exe.write_bytes(b'Not executable;must never run')
  p=subprocess.run([sys.executable,'-X','utf8',str(R/'scripts/solidify_flash.py'),'--bw',str(exe)],capture_output=True,text=True,encoding='utf8',creationflags=0x08000000)
  assert p.returncode==0 and 'DRY RUN ONLY' in p.stdout,p.stdout+p.stderr
 results.append(dict(test='Flash_default_dry_run_does_not_execute_programmer',status='PASS'))
demo=R/'assets/Synthetic_Demo.img'
if demo.exists():assert alpha_package.inspect(demo,True)['visible']==5;results.append(dict(test='own_geometric_video_4standard_images_container',status='PASS'))
O=R/'runtime/tests';O.mkdir(parents=True,exist_ok=True)
(O/'publication.json').write_text(json.dumps(dict(status='PASS_OFFLINE_REPOSITORY',tests=results,device_actions=False),ensure_ascii=False,indent=2),encoding='utf8')
print('PASS publication checks',len(results),'no device access')
