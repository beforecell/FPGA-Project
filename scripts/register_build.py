"""Register a natively built local project without replacing frozen inputs."""
from pathlib import Path
import sys,json,hashlib,shutil,argparse,datetime
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'host'))
import device_tools,project_paths
p=argparse.ArgumentParser();p.add_argument('role',choices=['player','tf-maintenance','uart-maintenance','fallback-art9']);p.add_argument('build',type=Path);a=p.parse_args()
m=device_tools.verify_build(a.build)
frozen=json.loads((R/'fpga'/a.role/'verification/build_manifest.json').read_text(encoding='utf8'))
if {k:v.upper() for k,v in m['source_sha256'].items()}!={k:v.upper() for k,v in frozen['source_sha256'].items()}:raise ValueError('Changed build inputs need a separate experimental version,not this frozen profile')
target=R/'runtime/firmware'/(a.role+'_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
for n in [*m['source_sha256'],'blackbox.bit','Build.ps1','Download-SRAM.ps1','verification/build_manifest.json']:
 src=a.build/n;dst=target/n;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
old=project_paths.pointer(a.role)
old.update(project_relative=target.relative_to(R).as_posix(),bit_sha256=m['bit_sha256'],local_build=True,diagnostic_only=True,board_verified=False,configuration_status='INHERITED_READBACK_ISSUE_NOT_RETESTED',scope='Locally registered native-positive build;not independently board-accepted')
f=R/'runtime/local-firmware.json';items=json.loads(f.read_text(encoding='utf8')) if f.exists() else {};items[a.role]=old;f.write_text(json.dumps(items,ensure_ascii=False,indent=2),encoding='utf8')
print('Registered',a.role,target,'Restart GUI;local build remains diagnostic.No device access.')
