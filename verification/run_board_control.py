from pathlib import Path
import subprocess,re,json,sys
root=Path(__file__).resolve().parent.parent
base='baseline_src' if '--baseline' in sys.argv else 'src'
out=root/'verification'/('results_board_baseline' if base=='baseline_src' else 'results_board')
out.mkdir(exist_ok=True)
h=root/base/'user_source/hdl_source'
v=root/'verification'
bin=Path(r'C:/intelFPGA_pro/20.4/modelsim_ase/win32aloem')
do=out/'run.do'
do.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nrun -all\nquit -code 0 -force\n',encoding='ascii')
cmds=[
 [bin/'vlib.exe','work'],
 [bin/'vlog.exe','-sv','-work','work',h/'key_events.v',h/'SD/bmp_read.v',h/'SD/sd_card_bmp.v',h/'SD/frame_fifo_read.v',h/'media_present_bridge.v',v/'board_sd_model.v',v/'tb_board_control.sv'],
 [bin/'vsim.exe','-c','-onfinish','exit','-voptargs=+acc','work.tb_board_control','-do',do]]
results=[]
for i,c in enumerate(cmds):
 p=subprocess.run(list(map(str,c)),cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
 s=p.stdout.decode('utf-8',errors='replace');(out/(str(i)+'.log')).write_text(s,encoding='utf-8')
 ok=p.returncode==0 and not re.search(r'\*\* (?:Error|Fatal)',s)
 if i==2:ok=ok and 'PASS tb_board_control' in s
 results.append(dict(step=i,passed=ok)); print(s[-3500:],flush=True)
 (out/'results.json').write_text(json.dumps(results,indent=2))
 if not ok:raise SystemExit(1)
