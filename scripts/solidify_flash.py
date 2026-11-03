"""Documented vendor BW flow;default dry-run,explicit execution+confirmation.
This tool never runs from import or GUI startup.No TF operations.
"""
from pathlib import Path
import sys,argparse,subprocess,tempfile,re,datetime
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'host'))
import project_paths,device_tools
def check_log(text,code):
 diagnostics='\n'.join(l for l in text.splitlines() if not re.match(r'^\s*RUN-\d+\s*:',l))
 if code or re.search(r'(?i)\b(?:ERROR|FATAL|failed|failure)\b|invalid command',diagnostics):raise RuntimeError('Vendor BW reported an error;Flash state not accepted')
 for pattern in [r'Chip validation success:\s*EG4S20BG256\b',r'SPI Flash ID is:\s*ef\b',r'finish command "program_spi\s',r'-m verify_spi\b',r'finish command "download -mode program_spi\s']:
  if not re.search(pattern,text,re.I):raise RuntimeError('Missing write/verify evidence')
 if not re.search(r'finish command "program\s',re.split(r'-m verify_spi\b',text,flags=re.I)[-1]):raise RuntimeError('Flash verify incomplete')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--bw',type=Path,required=True);p.add_argument('--execute',action='store_true');a=p.parse_args()
 if not a.bw.is_file() or a.bw.name.lower()!='bw_commands_prompt.exe':p.error('Use bin/bw_commands_prompt.exe,not td_commands_prompt.exe')
 project=R/project_paths.relative('player');m=device_tools.verify_build(project)
 command='download -mode program_spi -bit {ARTF.bit} -chip EG4S20BG256 -flashsize 16 -cable 0 -spd 6 -v'
 print('Target:HX4S20C EG4S20BG256,expected W25Q16 2MiB;replaces boot Flash,TF untouched.Confirm actual board and back up current Flash first.')
 print('bit SHA256:',m['bit_sha256']);print(command)
 if not a.execute:print('DRY RUN ONLY.No programmer or hardware was invoked.');return
 if input('Type exactly FLASH ARTF to authorize overwrite: ')!='FLASH ARTF':raise SystemExit('Cancelled;no hardware access')
 out=R/'runtime/flash'/datetime.datetime.now().strftime('%Y%m%d_%H%M%S');out.mkdir(parents=True,exist_ok=False)
 with device_tools.board_access(),tempfile.TemporaryDirectory(prefix='artf_bw_') as t:
  t=Path(t);(t/'ARTF.bit').write_bytes((project/'blackbox.bit').read_bytes());script=t/'write.tcl'
  script.write_text(command+'\nexit 0\n',encoding='ascii')
  proc=subprocess.run([str(a.bw.resolve()),script.as_posix()],cwd=t,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,creationflags=0x08000000)
  text=proc.stdout.decode('utf8',errors='replace');(out/'vendor.log').write_text(text,encoding='utf8');check_log(text,proc.returncode)
 print('Flash write and vendor verification complete.Cold power-cycle and separate runtime/HDMI/audio acceptance still required.',out)
if __name__=='__main__':main()
