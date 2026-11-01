"""Static arithmetic, asset, and mapped-netlist checks; no RTL simulation."""
from pathlib import Path
import argparse, array, hashlib, json, math, re, wave

parser=argparse.ArgumentParser()
parser.add_argument('--gate', type=Path, required=True)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
out=root/'verification/static_stabilityfix_20261002'
out.mkdir(exist_ok=True)
netlist=args.gate.read_text(encoding='utf-8-sig')
old_gate=root/'build_displayfix_20261002/compile_runs/20261002_151808_032077/verification/td_build/display_gate.v'
old_netlist=old_gate.read_text(encoding='utf-8-sig')
old_req=next(line for line in old_netlist.splitlines() if 'Sdr_ref_req_syn_1  (' in line)
new_req=next(line for line in netlist.splitlines() if 'Sdr_ref_req_syn_1  (' in line)
assert "1'b0" in old_req
assert "1'b0" not in new_req and 'App_ref_req' in new_req
assert 'frame_read_write_m0/App_ref_req_reg ' in netlist
assert 'frame_read_write_m0/refresh_pending_reg ' in netlist
assert 'frame_read_write_m0/refresh_state' in netlist
assert 'u_wav_scene_player/fallback_sync_reg[0]' in netlist
assert 'u_wav_scene_player/fallback_sync_reg[1]' in netlist
assert 'u_wav_scene_player/fallback_sync_reg[2]' in netlist
# The counter comparison must survive mapping along with the ten low bits.
for bit in range(10):
    assert f'frame_read_write_m0/refresh_count_reg[{bit}]' in netlist
(out/'refresh_netlist_evidence.txt').write_text('OLD: '+old_req+'\nNEW: '+new_req+'\n',encoding='utf-8')

clamp=lambda x:max(0,min(255,x))
for gain in range(257):
    for pixel in range(256):
        assert clamp(((pixel-128)*gain)//128+128)==clamp((pixel*gain)//128-gain+128)
mults=re.findall(r'  EG_PHY_MULT18 #\(.*?\)\);',netlist,re.S)
color_mults=[m for m in mults if 'u_video_rgb_contrast' in m]
assert len(color_mults)==2
for channel in ('23:16','15:8','7:0'):
    assert any("1'b0,\\u_video_rgb_contrast/rgb ["+channel+']' in m for m in color_mults)
for m in color_mults:
    assert '.MODE("MULT9X9C")' in m
    assert "5'b00000,\\u_scene_caption_overlay/contrast [8:5]" in m
    if 'u_scene_caption_overlay/volume' in m:
        assert '.SIGNEDAMUX("0")' in m
(out/'contrast_dsp_audit.txt').write_text('\n\n'.join(color_mults),encoding='utf-8')

# Read the actual parenthesized macros, including their textual expansion.
defs={}
for name,expr in re.findall(r'`define\s+(\w+)\s+([^\n]+)',(root/'src/user_source/hdl_source/include/global_def.v').read_text()):
    for dep,value in defs.items(): expr=expr.replace('`'+dep,'('+str(value)+')')
    assert re.fullmatch(r'[\d ()*/]+',expr),expr
    defs[name]=eval(expr.replace('/','//'),{'__builtins__':{}},{})
assert defs['SDR_CLK_PERIOD']==25 and defs['SELF_REFRESH_INTERVAL']==1250
refresh_ticks=defs['SELF_REFRESH_INTERVAL']//2
assert refresh_ticks==625

def meter(a):
    if a<1024: return a>>3
    if a<4096: return 128+((a-1024)>>5)
    if a<8192: return 224+((a-4096)>>7)
    return 256
mapped=[meter(a) for a in range(32769)]
assert mapped[0]==0 and mapped[-1]==256
assert all(0<=a<=b<=256 for a,b in zip(mapped,mapped[1:]))
assert all(a>=i//128 for i,a in enumerate(mapped))
assets=[]
for folder in (root/'content').glob('*v4*'):
    for path in sorted(folder.rglob('AUDIO[1-4].WAV')):
        with wave.open(str(path)) as w:
            assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(1,2,48000)
            pcm=array.array('h',w.readframes(w.getnframes()))
        # Default volume=256, WAV product >>>11. Full fade-in, before meter decay.
        scaled=[v//8 for v in pcm]
        peaks=sorted(max(abs(x) for x in scaled[n:n+800]) for n in range(0,len(scaled),800))
        quantiles=[peaks[int((len(peaks)-1)*q)] for q in (.5,.9,1)]
        assets.append({'file':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                       'old_width_p50_p90_max':[a>>7 for a in quantiles],
                       'new_width_p50_p90_max':[meter(a) for a in quantiles]})
assert len(assets)==4
# Conservative interface budget, not a simulator result or a hardware measurement.
# 256 write strobes + 20 handoff/tail clocks + 40 refresh clocks + 16 read-start clocks.
wait_clocks=256+20+40+16
reserve_pixels=256
consumed_pixels=math.ceil(wait_clocks*25/40)+4 # FIFO occupancy CDC lag
assert consumed_pixels<reserve_pixels
assert wait_clocks<refresh_ticks
result={
    'old_refresh_request_tied_low':True,'new_refresh_request_has_registered_driver':True,
    'new_refresh_counter_and_state_retained':True,'refresh_clock_hz':40000000,
    'refresh_due_period_clocks':refresh_ticks,'refresh_due_period_us':refresh_ticks/40,
    'refresh_base_sweep_ms_2048_rows':refresh_ticks*2048/40000,
    'estimated_max_bus_wait_clocks':wait_clocks,'reserve_pixels':reserve_pixels,
    'estimated_pixels_consumed_with_cdc_margin':consumed_pixels,
    'budget_is_conservative_static_estimate':True,
    'contrast_arithmetic_cases':65792,'mapped_rgb_zero_extension_preserved':True,
    'meter_arithmetic_cases':32769,'meter_monotonic_and_silent_at_zero':True,
    'meter_height_old_new':[3,6],'meter_width':256,'natural_recording_meter_analysis':assets,
    'gate_sha256':hashlib.sha256(args.gate.read_bytes()).hexdigest(),
    'simulation_run':False,'hardware_tested':False}
(out/'static_result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
