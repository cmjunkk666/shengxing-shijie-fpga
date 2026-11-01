"""Run functional RTL and independent numeric checks. Encrypted HDMI/SDRAM are
not simulated here; the media bench exercises the real frame reader with a
bounded eight-cycle SDRAM response model. All output is isolated."""
from pathlib import Path
import argparse,subprocess,re,json,sys
here=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--modelsim-bin',default=r'C:\intelFPGA_pro\20.4\modelsim_ase\win32aloem')
a=parser.parse_args()
binpath=Path(a.modelsim_bin);out=here/'results_lesson3';out.mkdir(exist_ok=True)
hdl=here.parent/'src/user_source/hdl_source'
results=[]
def run(command,label,cwd=out,passed_marker=None,timeout=240):
    p=subprocess.run(list(map(str,command)),cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
    s=p.stdout.decode('utf-8',errors='replace')
    (out/(label+'.log')).write_text(s,encoding='utf-8')
    ok=p.returncode==0 and not re.search(r'\*\* (?:Error|Fatal)',s)
    if passed_marker: ok=ok and passed_marker in s
    results.append(dict(label=label,passed=ok,returncode=p.returncode))
    (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print(label, 'PASS' if ok else 'FAIL',flush=True)
    if not ok:
        print(s);raise SystemExit(1)
run([binpath/'vlib.exe','work'],'vlib')
sources=['audio/audio_cadence_monitor.v','audio/audio_sample_tick.v','audio/pcm_scene_audio.v','audio_arc_calculate.v',
         'key_events.v','media_present_bridge.v','reset_release_sync.v','SD/frame_fifo_read.v','video_rgb_to_axis_640x480.v',
         'SD/frame_fifo_write.v','SD/color_bar.v','SD/video_timing_data.v','SD/video_delay.v','IP/afifo_32_16_256.v']
tests=['tb_key_events','tb_audio_cadence','tb_audio_clock','tb_pcm_audio','tb_video_axis','tb_media_present','tb_frame_pipeline','tb_frame_writer']
run([binpath/'vlog.exe','-sv','+incdir='+str(hdl/'SD'),'-work','work',*[hdl/s for s in sources],here/'frame_fifo_write_reference.v',*[here/(s+'.sv') for s in tests]],'compile')
do=out/'run.do'
do.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nrun -all\nquit -code 0 -force\n',encoding='ascii')
for test in tests:
    for phase in ([1,3,7] if test=='tb_media_present' else [None]):
        plusargs=[] if phase is None else ['+MEM_PHASE='+str(phase)]
        label=test+('' if phase is None else '_phase'+str(phase))
        run([binpath/'vsim.exe','-c','-onfinish','exit','-voptargs=+acc','work.'+test,*plusargs,'-do',do],
            label,passed_marker='PASS '+test)
run([sys.executable,'-B',here/'check_pcm_reference.py'],'numeric_reference')
print('ALL SHARED AUDIO/VIDEO/KEY/WRITER REGRESSIONS PASSED')
