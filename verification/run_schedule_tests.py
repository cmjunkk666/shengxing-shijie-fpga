from pathlib import Path
import subprocess,re,json,sys
v=Path(__file__).resolve().parent;h=v.parent/'src/user_source/hdl_source';out=v/'results_schedule';out.mkdir(exist_ok=True)
b=Path(r'C:/intelFPGA_pro/20.4/modelsim_ase/win32aloem');results=[]
def run(cmd,label,marker=None):
 r=subprocess.run(list(map(str,cmd)),cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
 s=r.stdout.decode(errors='replace');(out/(label+'.log')).write_text(s,encoding='utf-8');ok=r.returncode==0 and not re.search(r'\*\* (?:Error|Fatal)',s) and (marker is None or marker in s)
 results.append(dict(test=label,passed=ok));(out/'results.json').write_text(json.dumps(results,indent=2));print(label,'PASS' if ok else 'FAIL',flush=True)
 if not ok:print(s);sys.exit(1)
run([b/'vlib.exe','work'],'vlib')
run([b/'vlog.exe','-sv','-work','work',h/'key_events.v',h/'SD/sd_card_bmp.v',v/'schedule_protocol_mocks.sv',v/'tb_player_schedule.sv'],'compile')
d=out/'run.do';d.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nrun -all\nquit -code 0 -force\n')
for case in ['0','1']:
 run([b/'vsim.exe','-c','-onfinish','exit','work.tb_player_schedule','+CASE='+case,'-do',d],'schedule_'+case,'PASS tb_player_schedule')
