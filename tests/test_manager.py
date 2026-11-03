from pathlib import Path
import os,shutil,subprocess,tempfile,json
R=Path(__file__).resolve().parents[1];T=Path(__file__).parent
iv=shutil.which('iverilog')
bins=Path(os.environ.get('IVERILOG_BIN',str(Path(iv).parent) if iv else 'MISSING_IVERILOG'))
assert (bins/'iverilog.exe').is_file(),'Install Icarus or set IVERILOG_BIN'
results=[]
with tempfile.TemporaryDirectory(prefix='alpha_manager_') as tmp:
 for name in ['manager_lag3','manager_lag3_random_seek','manager_lag3_rapid_epoch']:
  v=Path(tmp)/(name+'.vvp')
  p=subprocess.run([str(bins/'iverilog.exe'),'-g2012','-s','tb','-o',str(v),str(T/(name+'.sv')),str(R/'fpga/player/rtl/bb_replay_manager.v')],capture_output=True,text=True,encoding="utf8",errors="replace")
  assert p.returncode==0,p.stdout+p.stderr
  p=subprocess.run([str(bins/'vvp.exe'),str(v)],capture_output=True,text=True,encoding="utf8",errors="replace",timeout=60);assert p.returncode==0 and 'PASS' in p.stdout,p.stdout+p.stderr
  results.append(dict(test=name,output=p.stdout));print(p.stdout.strip())
O=R/'runtime/tests';O.mkdir(parents=True,exist_ok=True);(O/'manager_checks.json').write_text(json.dumps(dict(status='PASS_BEHAVIORAL_SLOT_MODEL',tests=results,hardware=False),indent=2),encoding='utf8')
