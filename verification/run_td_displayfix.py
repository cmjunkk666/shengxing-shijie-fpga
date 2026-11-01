"""Build a source snapshot with TD, preserving the project's existing GUI runs.

Exit 0: bit generated and reported setup/hold timing passes.
Exit 2: bit generated, but reported setup/hold timing is negative.
Exit 1: build failed. A bit file by itself is not a timing sign-off.
"""
from pathlib import Path
from datetime import datetime
import argparse, hashlib, json, re, shutil, subprocess

parser=argparse.ArgumentParser()
parser.add_argument('--td-exe',default=r'D:\anlu\bin\td_commands_prompt.exe')
parser.add_argument('--build-root',type=Path)
parser.add_argument('--audio-test-mode',type=int,choices=[0,1],default=0)
args=parser.parse_args()
here=Path(__file__).resolve().parent
root=here.parent
build_base=args.build_root or here/'td_final'
snapshot=build_base.resolve()/datetime.now().strftime('%Y%m%d_%H%M%S_%f')
snapshot.mkdir(parents=True,exist_ok=False)
shutil.copytree(root/'src',snapshot/'src',ignore=shutil.ignore_patterns('*_Runs','log','*.prj','*.db','*.log','*.logw'))
topfile=snapshot/'src/user_source/hdl_source/top_tf_hdmi_audio.v'
if args.audio_test_mode:
    text=topfile.read_text(encoding='utf-8-sig')
    text=text.replace('parameter AUDIO_TEST_MODE = 0;', 'parameter AUDIO_TEST_MODE = 1;')
    topfile.write_text(text,encoding='utf-8')
project=snapshot/'src/td_project'
name='HDMI1.4b_Transmitter_v1.0'
al=(project/(name+'.al')).read_text(encoding='utf-8-sig')
prj=re.sub(r'(<Project\b[^>]*?) Path="[^"]*"',r'\1',al,count=1)
prj=re.sub(r'\s*<Runs>.*?</Runs>','',prj,flags=re.S)
prj=re.sub(r'\s*<Project_Settings>.*?</Project_Settings>','',prj,flags=re.S)
(project/(name+'.prj')).write_text(prj,encoding='utf-8')
out=snapshot/'verification/td_build'
out.mkdir(parents=True)
tcl=(here/'run_td_displayfix.tcl').read_text(encoding='utf-8-sig')
if args.audio_test_mode:
    tcl=tcl.replace('displayfix_hdmi_a.bit','lesson3_test_1khz.bit')
    # Fixed-tone mapping differs; increase placement timing effort for the
    # existing BMP scan path. This changes placement, not timing constraints.
    tcl=tcl.replace('\nplace\n','\nset_param place effort high\nset_param place opt_timing high\nplace\n')
(snapshot/'verification/run_td.tcl').write_text(tcl,encoding='utf-8')
manifest=[{'path':p.relative_to(snapshot).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
          for p in sorted((snapshot/'src').rglob('*')) if p.is_file()]
(out/'source_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('Building snapshot:',snapshot,flush=True)
with (out/'build_console.log').open('wb') as log:
    proc=subprocess.run([args.td_exe,'../../verification/run_td.tcl'],cwd=project,stdout=log,stderr=subprocess.STDOUT,timeout=1800)
raw=(out/'build_console.log').read_bytes()
console=raw.decode('utf-8',errors='replace')
bit=out/('lesson3_test_1khz.bit' if args.audio_test_mode else 'displayfix_hdmi_a.bit')
ok=proc.returncode==0 and 'DISPLAYFIX_TD_BUILD_COMPLETE' in console and bit.is_file() and not re.search(r'\bERROR:|No nets matched|USR-8159 CRITICAL-WARNING',console)
summary={'process_returncode':proc.returncode,'bit_generated':ok,'hardware_tested':False,'audio_test_mode':args.audio_test_mode}
if ok:
    ts=(out/'lesson3_phy.ts').read_text(encoding='utf-8-sig')
    summary['setup_wns_ns']=float(re.search(r'SWNS:\s*([-\d.]+)',ts).group(1))
    summary['hold_wns_ns']=float(re.search(r'HWNS:\s*([-\d.]+)',ts).group(1))
    summary['reported_setup_hold_pass']=summary['setup_wns_ns']>=0 and summary['hold_wns_ns']>=0
    summary['bit_sha256']=hashlib.sha256(bit.read_bytes()).hexdigest()
(out/'build_result.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps(summary,indent=2))
print('Reports:',out)
raise SystemExit(1 if not ok else (0 if summary['reported_setup_hold_pass'] else 2))
