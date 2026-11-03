"""Re-run the sixteen recorded source-bound units;no hardware actions."""
from pathlib import Path
import os,shutil,subprocess,json,hashlib,tempfile
R=Path(__file__).resolve().parents[1]
E=R/'verification'
P=R/'fpga/player'
cert=json.loads((E/'rtl-certificate.json').read_text(encoding='utf8'))
bin_dir=os.environ.get('IVERILOG_BIN')
iverilog=str(Path(bin_dir)/'iverilog.exe') if bin_dir else shutil.which('iverilog')
vvp=str(Path(bin_dir)/'vvp.exe') if bin_dir else shutil.which('vvp')
if not iverilog or not vvp:raise SystemExit('Install Icarus or set IVERILOG_BIN')
O=R/'runtime/tests/historical_units';O.mkdir(parents=True,exist_ok=True)
records=[]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory(prefix='alpha_units_') as tmp:
    w=Path(tmp)
    for t in cert['tests']:
        name=t['test']['name'];bench=Path(__file__).parent/'历史单元'/(name+'.sv')
        assert sha(bench)==t['bench_sha256'],name
        files=[]
        for n,h in t['source_sha256'].items():
            p=P/n;assert sha(p)==h.lower(),n;files.append(p)
        output=w/(name+'.vvp')
        cmd=[iverilog,'-g2012','-I',str(P/'rtl'),'-s','tb','-o',str(output),str(bench),*map(str,files)]
        a=subprocess.run(cmd,cwd=w,capture_output=True,text=True,encoding='utf8',errors='replace',creationflags=0x08000000,timeout=60)
        (O/(name+'_compile.log')).write_text(a.stdout+a.stderr,encoding='utf8')
        assert a.returncode==0,name+' '+a.stderr
        a=subprocess.run([vvp,str(output)],cwd=w,capture_output=True,text=True,encoding='utf8',errors='replace',creationflags=0x08000000,timeout=180)
        (O/(name+'.log')).write_text(a.stdout+a.stderr,encoding='utf8')
        assert a.returncode==0 and 'PASS' in a.stdout,name+' '+a.stdout+a.stderr
        records.append(dict(name=name,status='PASS',bench_sha256=sha(bench),source_sha256=t['source_sha256']))
        print('PASS',name,flush=True)
(O/'checks.json').write_text(json.dumps(dict(status='PASS_16_FINAL_SOURCE_BOUND_UNITS',scope='Icarus RTL models,not physical pins/timing/full player',records=records),ensure_ascii=False,indent=2),encoding='utf8')
