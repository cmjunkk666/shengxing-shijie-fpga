"""Publish only a source-matched, timing-passing waveform display build."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,sys
parser=argparse.ArgumentParser()
parser.add_argument('snapshot',type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
snapshot=args.snapshot.resolve()
reports=snapshot/'verification/td_build'
release=root/'build_wavegain_20261002'
checks=root/'verification/static_wavegain_20261002'
backup=root/'_backup/wavegain_20261002_161735'
result=json.loads((reports/'build_result.json').read_text())
assert result['bit_generated'] and result['reported_setup_hold_pass'],result
manifest=json.loads((reports/'source_manifest.json').read_text())
for entry in manifest:
 path=Path(entry['path'])
 if path.suffix=='.prj':
  project=(root/path.with_suffix('.al')).read_text(encoding='utf-8-sig')
  project=re.sub(r'(<Project\b[^>]*?) Path="[^"]*"',r'\1',project,count=1)
  project=re.sub(r'\s*<Runs>.*?</Runs>','',project,flags=re.S)
  project=re.sub(r'\s*<Project_Settings>.*?</Project_Settings>','',project,flags=re.S)
  assert project==(snapshot/path).read_text(encoding='utf-8-sig')
 else:
  assert hashlib.sha256((root/path).read_bytes()).hexdigest()==entry['sha256'],entry['path']
assert 'Errors: 0, Warnings: 0' in (checks/'compile.log').read_text(errors='replace')
subprocess.run([sys.executable,'-B',str(root/'verification/check_wavegain.py'),
                '--gate',str(reports/'display_gate.v')],check=True,stdout=subprocess.DEVNULL)
static=json.loads((checks/'static_result.json').read_text())
prior=root/'build_stabilityfix_20261002'
prior_manifest=json.loads((prior/'release_manifest.json').read_text(encoding='utf-8'))
assert hashlib.sha256((prior/'stabilityfix_hdmi_a.bit').read_bytes()).hexdigest()==prior_manifest['build']['bit_sha256']
warning_pattern=r'([A-Z]+-\d+) (?:CRITICAL-)?WARNING'
old_log=(prior/'build_console.log').read_text(errors='replace')
new_log=(reports/'build_console.log').read_text(errors='replace')
new_categories=sorted(set(re.findall(warning_pattern,new_log))-set(re.findall(warning_pattern,old_log)))
assert not new_categories,new_categories
assert not re.search(r'No nets matched|USR-8159 CRITICAL-WARNING|\bERROR:',new_log)
area=(reports/'lesson3_phy.area').read_text()
resources={key:int(re.search(r'^#'+pattern+r'\s+(\d+)',area,re.M).group(1))
           for key,pattern in [('lut','lut'),('registers','reg'),('bram9k','bram'),('dsp','dsp')]}
assert resources['dsp']==prior_manifest['resources']['dsp']
assert resources['bram9k']<=prior_manifest['resources']['bram9k']+1
release.mkdir(exist_ok=True)
for file in reports.iterdir():
 if file.is_file() and file.suffix in ('.bit','.json','.log','.ts','.timing','.area'):
  shutil.copy2(file,release/file.name)
shutil.copytree(checks,release/'verification',dirs_exist_ok=True,ignore=shutil.ignore_patterns('work'))
for name in ('check_wavegain.py','package_wavegain.py','run_td_wavegain.py','run_td_wavegain.tcl'):
 shutil.copy2(root/'verification'/name,release/'verification'/name)
shutil.copy2(root/'tools/generate_audio_view_labels.py',release/'verification/generate_audio_view_labels.py')
bit=release/'wavegain_hdmi_a.bit'
assert hashlib.sha256(bit.read_bytes()).hexdigest()==result['bit_sha256']
metadata={
 'bit':bit.name,'snapshot':str(snapshot),'backup':str(backup),'changed_files':static['changed_files'],
 'build':result,'resources':resources,'previous_resources':prior_manifest['resources'],
 'syntax_errors':0,'syntax_warnings':0,'new_warning_categories':new_categories,
 'inherited_ip_warnings_remain':True,
 'waveform':'Signed extrema per 16 samples at finest display precision, one scale for each 2048-sample snapshot; at most 4x visual gain.',
 'scope':'WAVE renderer and its Chinese adaptive-scale title only.',
 'gallery_changed':False,'audio_pcm_changed':False,'level_history_changed':False,'yellow_meter_changed':False,
 'hdmi_port':'A','simulation_run':False,'hardware_tested':False,'sd_card_modified':False,
 'previous_bit_preserved':str(prior/'stabilityfix_hdmi_a.bit')}
(release/'release_manifest.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(metadata,ensure_ascii=False,indent=2))
