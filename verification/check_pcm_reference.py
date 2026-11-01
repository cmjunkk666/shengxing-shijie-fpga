from pathlib import Path
import math,json
out=Path(__file__).resolve().parent/'results_lesson3'
errors=[];count=0
for name in ['pcm_trace.txt','tone_trace.txt']:
    for line in (out/name).read_text().splitlines():
        idx,phase,gain,actual=map(int,line.split()[:4])
        wave=round(12000*math.sin(2*math.pi*(phase>>24)/256))
        value=wave*gain/256
        expected=math.floor(value+0.5) if value>=0 else math.ceil(value-0.5)
        expected=max(-32768,min(32767,expected))
        if actual!=expected: errors.append([name,idx,expected,actual])
        count+=1
for line in (out/'sine_trace.txt').read_text().splitlines():
    address,actual=map(int,line.split())
    expected=round(12000*math.sin(2*math.pi*address/256))
    if actual!=expected: errors.append(['sine',address,expected,actual])
qcount=0
for line in (out/'quantize_trace.txt').read_text().splitlines():
    val,actual=map(int,line.split())
    expected=(abs(val)+128)//256
    if val<0: expected=-expected
    expected=max(-32768,min(32767,expected))
    if actual!=expected: errors.append(['quantize',val,expected,actual])
    qcount+=1

rows=[list(map(int,line.split())) for line in (out/'pcm_trace.txt').read_text().splitlines()]
tone=[list(map(int,line.split())) for line in (out/'tone_trace.txt').read_text().splitlines()]
freqs=[[523.2511306,659.2551138,783.9908720,659.2551138],
       [440,523.2511306,659.2551138,523.2511306],
       [587.3295358,659.2551138,880,659.2551138],
       [261.6255653,391.9954360,523.2511306,391.9954360]]
phase_checks=0
for previous,current in zip(rows,rows[1:]):
    idx=current[0]
    if current[0]!=previous[0]+1: continue
    if 500<idx<12100 or 24600<idx<37000 or 37400<idx<65000:
        if current[7] != (previous[7]+1)%12000:
            errors.append(['note_duration',idx,previous[7],current[7]])
        if current[6] != (previous[6]+(previous[7]==11999))%4:
            errors.append(['note_index',idx,previous[6],current[6]])
        expected_phase=0 if previous[7]==0 else (
            previous[1]+round(freqs[previous[4]][previous[6]]*2**32/48000))%2**32
        if current[1]!=expected_phase: errors.append(['scene_phase',idx,expected_phase,current[1]])
        phase_checks+=1
for previous,current in zip(tone,tone[1:]):
    idx=current[0]
    if current[0]!=previous[0]+1: continue
    if 20<idx<24000 or 24310<idx<65000:
        expected=(previous[1]+round(1000*2**32/48000))%2**32
        if current[1]!=expected: errors.append(['1khz_phase',idx,expected,current[1]])
        phase_checks+=1
if rows[10][5]!=0 or rows[250][5]!=256 or rows[12010][5]!=0:
    errors.append(['240_sample_envelope_endpoints'])
result={'passed':not errors,'pcm_samples_compared':count,'sine_addresses':256,
        'quantizer_cases':qcount,'frequency_note_checks':phase_checks,'errors':errors[:20]}
(out/'numeric_reference.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
if errors: raise SystemExit(1)
