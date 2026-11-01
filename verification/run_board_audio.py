from pathlib import Path
import subprocess,re,json
v=Path(__file__).resolve().parent;h=v.parent/'src/user_source/hdl_source';out=v/'results_board_audio';out.mkdir(exist_ok=True)
b=Path(r'C:/intelFPGA_pro/20.4/modelsim_ase/win32aloem')
do=out/'run.do';do.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nrun -all\nquit -code 0 -force\n',encoding='ascii')
cs=[[b/'vlib.exe','work'],[b/'vlog.exe','-sv',h/'reset_release_sync.v',h/'audio/pcm_scene_audio.v',v/'tb_board_audio_reset.sv'],[b/'vsim.exe','-c','-onfinish','exit','-voptargs=+acc','work.tb_board_audio_reset','-do',do]]
results=[]
for i,c in enumerate(cs):
 p=subprocess.run(list(map(str,c)),cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
 s=p.stdout.decode('utf-8',errors='replace');(out/(str(i)+'.log')).write_text(s,encoding='utf-8');print(s[-2500:],flush=True)
 ok=p.returncode==0 and not re.search(r'\*\* (?:Error|Fatal)',s)
 if i==2:ok=ok and 'PASS tb_board_audio_reset' in s
 results.append(dict(step=i,passed=ok));(out/'results.json').write_text(json.dumps(results,indent=2))
 if not ok:raise SystemExit(1)
