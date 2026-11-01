"""Arithmetic and mapped-hardware audits only; does not run an RTL simulator."""
from pathlib import Path
import argparse,array,difflib,hashlib,json,re,wave
from PIL import Image,ImageDraw,ImageFont
parser=argparse.ArgumentParser()
parser.add_argument('--gate',type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
out=root/'verification/static_wavegain_20261002'
out.mkdir(exist_ok=True)
backup=root/'_backup/wavegain_20261002_161735'

# This release changes the green snapshot renderer and its mode label only.
changed=[];diff=[]
for folder in ('src','tools'):
 for file in (root/folder).rglob('*'):
  if not file.is_file() or file.suffix not in ('.v','.vh','.sdc','.py'):continue
  old=backup/file.relative_to(root)
  if old.exists() and old.read_text(encoding='utf-8-sig')==file.read_text(encoding='utf-8-sig'):continue
  changed.append(file.relative_to(root).as_posix())
  diff.extend(difflib.unified_diff(old.read_text(encoding='utf-8-sig').splitlines(True) if old.exists() else [],
              file.read_text(encoding='utf-8-sig').splitlines(True),fromfile=str(old),tofile=str(file)))
assert set(changed)=={'src/user_source/hdl_source/audio/pcm_wave_overlay.v',
 'src/user_source/hdl_source/audio/audio_view_labels.vh','tools/generate_audio_view_labels.py'},changed
(out/'changes.diff').write_text(''.join(diff),encoding='utf-8')

src=(root/'src/user_source/hdl_source/audio/pcm_wave_overlay.v').read_text()
body=src.split('function [3:0] snapshot_shift;',1)[1].split('endfunction',1)[0]
thresholds=[(int(p),int(s)) for p,s in re.findall(r"peak<=16'd(\d+)\)snapshot_shift=4'd(\d+)",body)]
fallback=int(re.search(r"else snapshot_shift=4'd(\d+)",body).group(1))
assert thresholds==[(1248,5),(2496,6),(4992,7),(9984,8),(19968,9)] and fallback==10
def shift(peak):
 return next((s for p,s in thresholds if peak<=p),fallback)
for peak in range(32769):
 s=shift(peak)
 assert 5<=s<=10
 assert -39<=(-peak>>s)<=0<=(peak>>s)<=39
 if s>5:assert peak>39*(1<<(s-1))
 if peak:assert shift(peak)>=shift(peak-1)
# One scale preserves order within each snapshot, with no samplewise clipping.
for s in range(5,11):
 vals=[v>>s for v in range(-32768,32768)]
 assert all(a<=b for a,b in zip(vals,vals[1:]))
 assert (0>>s)==0
 for v in range(max(-32768,-39*(1<<s)),min(32767,39*(1<<s))+1):
  assert (v>>5)>>(s-5)==v>>s
  bits=(v>>5) & 2047
  rendered=((bits>>(s-5)) | ((256-(1<<(16-s))) if v<0 and s>8 else 0)) & 255
  signed=rendered-256 if rendered&128 else rendered
  assert signed==v>>s

rom=root/'src/user_source/hdl_source/audio/audio_view_labels.vh'
oldrom=backup/rom.relative_to(root)
words=lambda p:[int(v,16) for v in re.findall(r"<= 16'h([0-9a-f]{4})",p.read_text())]
new_words=words(rom);old_words=words(oldrom)
assert len(new_words)==512 and new_words[256:]==old_words[256:]
assets=[];examples=[]
folder=next((root/'content').glob('*v4*'))/'card_files'
for number in range(1,5):
 path=folder/f'AUDIO{number}.WAV'
 with wave.open(str(path)) as w:
  assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(1,2,48000)
  samples=array.array('h',w.readframes(w.getnframes()))
 peaks=[];heights=[];windows=[];scales={}
 for start in range(0,len(samples)-2047,2048):
  a=[v//8 for v in samples[start:start+2048]] # current full gain PCM, no fades
  peak=max(abs(v) for v in a);s=shift(peak)
  assert max(shift(abs(v)) for v in a)==s
  lo=[min(a[i:i+16]) for i in range(0,2048,16)]
  hi=[max(a[i:i+16]) for i in range(0,2048,16)]
  for i,(l,h) in enumerate(zip(lo,hi)):
   assert (l>>s)==min(v>>s for v in a[16*i:16*i+16])
   assert (h>>s)==max(v>>s for v in a[16*i:16*i+16])
  peaks.append(min(39,peak//128));heights.append(peak>>s)
  scales[str(s)]=scales.get(str(s),0)+1
  windows.append((peak,start/48000,lo,hi,s))
 idx=len(peaks)//2
 assets.append({'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                'snapshots':len(peaks),'old_median_half_height_px':sorted(peaks)[idx],
                'new_median_half_height_px':sorted(heights)[idx],'scale_shift_counts':scales})
 if number in (3,4):examples.append((number,sorted(windows,key=lambda v:v[0])[idx]))

# Side-by-side evidence is a software rendering of actual PCM, not a board capture.
canvas=Image.new('RGB',(1120,370),'#101b28');draw=ImageDraw.Draw(canvas)
font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',16)
draw.text((20,8),'Actual WAV samples, default volume | software preview, not board capture',font=font,fill='#e8f2ff')
for row,(number,(peak,time,lo,hi,s)) in enumerate(examples):
 y=44+row*158
 for col in range(2):
  x=20+col*550
  draw.text((x,y),f'AUDIO{number} @ {time:.2f}s   '+('BEFORE /128' if col==0 else f'AFTER /{1<<s}'),font=font,fill='#e8f2ff')
  top=y+27;center=top+48
  draw.rectangle((x,top,x+512,top+96),fill='#0c1520',outline='#60bfa0')
  draw.line((x,center,x+512,center),fill='#35485c')
  for k,(l,h) in enumerate(zip(lo,hi)):
   a=max(-39,min(39,l>>7)) if col==0 else l>>s
   b=max(-39,min(39,h>>7)) if col==0 else h>>s
   draw.rectangle((x+4*k,center-b,x+4*k+3,center-a),fill='#60e8b0')
canvas.save(out/'wave_before_after.png')

result={'changed_files':changed,'scale_peak_cases':32769,'signed_samples_per_scale':65536,
 'max_visual_gain_relative_to_previous':4,'one_scale_per_complete_snapshot':True,
 'time_window_ms':2048/48,'extrema_at_display_precision_preserved':True,'silence_remains_zero':True,
 'reduced_precision_exact_for_all_supported_scales':True,
 'audio_pcm_unchanged':True,'level_history_unchanged':True,'yellow_meter_unchanged':True,
 'gallery_unchanged':True,'assets':assets,'simulation_run':False,'hardware_tested':False}
if args.gate:
 netlist=args.gate.read_text(encoding='utf-8-sig')
 assert 'u_pcm_wave_overlay/wave_shift' in netlist
 assert 'u_pcm_wave_overlay/capture_shift' in netlist
 assert 'u_pcm_wave_overlay/samples1' in netlist
 # Retain the proven color and SDRAM fixes in the new physical build.
 req=next(line for line in netlist.splitlines() if 'Sdr_ref_req_syn_1  (' in line)
 assert "1'b0" not in req and 'App_ref_req' in req
 assert 'frame_read_write_m0/App_ref_req_reg ' in netlist
 mults=re.findall(r'  EG_PHY_MULT18 #\(.*?\)\);',netlist,re.S)
 colors=[m for m in mults if 'u_video_rgb_contrast' in m]
 for channel in ('23:16','15:8','7:0'):
  assert any("1'b0,\\u_video_rgb_contrast/rgb ["+channel+']' in m for m in colors)
 result.update({'gate_sha256':hashlib.sha256(args.gate.read_bytes()).hexdigest(),
                'mapped_adaptive_scale_retained':True,'refresh_request_retained':True,
                'rgb_multiplier_zero_extension_retained':True})
(out/'static_result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
