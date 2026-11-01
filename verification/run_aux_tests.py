from pathlib import Path
import subprocess,re,json,sys
v=Path(__file__).resolve().parent;h=v.parent/'src/user_source/hdl_source';out=v/'results_aux';out.mkdir(exist_ok=True)
b=Path(r'C:/intelFPGA_pro/20.4/modelsim_ase/win32aloem');results=[]
def run(cmd,label,marker=None):
 r=subprocess.run(list(map(str,cmd)),cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
 s=r.stdout.decode(errors='replace');(out/(label+'.log')).write_text(s,encoding='utf-8');ok=r.returncode==0 and not re.search(r'\*\* (?:Error|Fatal)',s) and (marker is None or marker in s)
 results.append(dict(test=label,passed=ok));(out/'results.json').write_text(json.dumps(results,indent=2));print(label,'PASS' if ok else 'FAIL',flush=True)
 if not ok:print(s);sys.exit(1)
run([b/'vlib.exe','work'],'vlib')
files=['SD/frame_read_write.v','SD/frame_fifo_read.v','SD/frame_fifo_write.v','IP/afifo_16_32_256.v','IP/afifo_32_16_256.v','player_osd.v']
run([b/'vlog.exe','-sv','-work','work',*[h/x for x in files],v/'tb_writer_abort.sv',v/'tb_frame_pair_reset.sv',v/'tb_osd.sv'],'compile')
d=out/'run.do';d.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nrun -all\nquit -code 0 -force\n')
for test in ['tb_writer_abort','tb_frame_pair_reset','tb_osd']:
 run([b/'vsim.exe','-c','-onfinish','exit','work.'+test,'-do',d],test,'PASS '+test)
import struct,zlib
for ppm in out.glob('*.ppm'):
 raw=ppm.read_bytes().split(b'\n',3)[3];w=640;hh=480;assert len(raw)==w*hh*3
 def chunk(typ,data):return struct.pack('>I',len(data))+typ+data+struct.pack('>I',zlib.crc32(typ+data)&0xffffffff)
 png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,hh,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(b'\0'+raw[y*w*3:(y+1)*w*3] for y in range(hh))))+chunk(b'IEND',b'')
 ppm.with_suffix('.png').write_bytes(png)
