from pathlib import Path
import subprocess,re,json,sys
v=Path(__file__).resolve().parent;h=v.parent/'src/user_source/hdl_source';out=v/'results_cache_final';out.mkdir(exist_ok=True)
b=Path(r'C:/intelFPGA_pro/20.4/modelsim_ase/win32aloem');results=[]
def run(cmd,label,marker=None,timeout=1800):
 r=subprocess.run(list(map(str,cmd)),cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
 s=r.stdout.decode(errors='replace');(out/(label+'.log')).write_text(s,encoding='utf-8')
 ok=r.returncode==0 and not re.search(r'\*\* (?:Error|Fatal)',s) and (marker is None or marker in s)
 results.append(dict(test=label,passed=ok));(out/'results.json').write_text(json.dumps(results,indent=2));print(label,'PASS' if ok else 'FAIL',flush=True)
 if not ok:print(s);sys.exit(1)
run([b/'vlib.exe','work'],'vlib')
sources=['storage/fat32_media.v','storage/bmp_stream_decoder.v','key_events.v','SD/sd_card_bmp.v',
 'SD/frame_read_write.v','SD/frame_fifo_read.v','SD/frame_fifo_write.v','SD/color_bar.v','SD/video_timing_data.v','SD/video_delay.v',
 'IP/afifo_16_32_256.v','IP/afifo_32_16_256.v','video_rgb_to_axis_640x480.v','media_present_bridge.v']
run([b/'vlog.exe','-sv','+incdir='+str(h/'SD'),'-work','work',*[h/x for x in sources],v/'fat_image_model.sv',v/'cache_sector_model.sv',v/'tb_cache_pipeline.sv'],'compile')
d=out/'run.do';d.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nrun -all\nquit -code 0 -force\n')
for case in (sys.argv[1:] or ['0']):
 run([b/'vsim.exe','-c','-onfinish','exit','work.tb_cache_pipeline','+CASE='+case,'-do',d],'cache_'+case,'PASS tb_cache_pipeline')
