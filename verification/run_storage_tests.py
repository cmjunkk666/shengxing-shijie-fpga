from pathlib import Path
import subprocess,re,sys,json
v=Path(__file__).resolve().parent;h=v.parent/'src/user_source/hdl_source';out=v/'results_456';out.mkdir(exist_ok=True)
b=Path(r'C:/intelFPGA_pro/20.4/modelsim_ase/win32aloem');results=[]
def run(cmd,label,marker=None,timeout=300):
 r=subprocess.run(list(map(str,cmd)),cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
 s=r.stdout.decode(errors='replace');(out/(label+'.log')).write_text(s,encoding='utf-8')
 ok=r.returncode==0 and not re.search(r'\*\* (?:Error|Fatal)',s) and (marker is None or marker in s)
 results.append(dict(test=label,passed=ok));(out/'results.json').write_text(json.dumps(results,indent=2))
 print(label,'PASS' if ok else 'FAIL',flush=True)
 if not ok:print(s);sys.exit(1)
run([b/'vlib.exe','work'],'vlib')
sources=[*sorted((h/'storage').glob('*.v')),h/'key_events.v',h/'SD/sd_card_bmp.v',h/'SD/frame_fifo_write.v',v/'fat_image_model.sv',v/'tb_fat32_media.sv',v/'tb_sd_service.sv']
run([b/'vlog.exe','-sv','-work','work',*sources],'compile_storage')
d=out/'run.do';d.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nrun -all\nquit -code 0 -force\n')
run([b/'vsim.exe','-c','-onfinish','exit','-voptargs=+acc','work.tb_fat32_media','-do',d],'tb_fat32_media','PASS tb_fat32_media')

run([b/'vsim.exe','-c','-onfinish','exit','-voptargs=+acc','work.tb_sd_service','-do',d],'tb_sd_service','PASS tb_sd_service')
