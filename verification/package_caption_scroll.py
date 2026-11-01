"""Package a source-matched, timing-passing default subtitle scroll build."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, subprocess, sys

parser = argparse.ArgumentParser()
parser.add_argument('snapshot', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
snapshot = args.snapshot.resolve()
reports = snapshot / 'verification/td_build'
release = root / 'build_caption_scroll_20261004'
checks = root / 'verification/static_caption_scroll_20261004'
backup = root / '_backup/caption_scroll_20261004_190311'
previous = root / 'build_logic_power_20261002'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
result = json.loads((reports / 'build_result.json').read_text())
assert result['bit_generated'] and result['reported_setup_hold_pass'] and result['audio_test_mode'] == 0, result
for entry in json.loads((reports / 'source_manifest.json').read_text()):
    path = Path(entry['path'])
    if path.suffix == '.prj':
        project = (root / path.with_suffix('.al')).read_text(encoding='utf-8-sig')
        project = re.sub(r'(<Project\b[^>]*?) Path="[^"]*"', r'\1', project, count=1)
        project = re.sub(r'\s*<Runs>.*?</Runs>', '', project, flags=re.S)
        project = re.sub(r'\s*<Project_Settings>.*?</Project_Settings>', '', project, flags=re.S)
        assert project == (snapshot / path).read_text(encoding='utf-8-sig')
    else:
        assert digest(root / path) == entry['sha256'], entry['path']
assert 'Errors: 0, Warnings: 0' in (checks / 'compile.log').read_text(errors='replace')
subprocess.run([sys.executable, '-B', str(root / 'verification/check_caption_scroll.py'),
                '--gate', str(reports / 'display_gate.v')], check=True, stdout=subprocess.DEVNULL)
static = json.loads((checks / 'static_result.json').read_text())
old = json.loads((previous / 'release_manifest.json').read_text(encoding='utf-8'))
assert digest(previous / 'logic_power_hdmi_a.bit') == old['build']['bit_sha256']
warning_pattern = r'([A-Z]+-\d+) (?:CRITICAL-)?WARNING'
new_log = (reports / 'build_console.log').read_text(errors='replace')
old_log = (previous / 'build_console.log').read_text(errors='replace')
new_categories = sorted(set(re.findall(warning_pattern, new_log)) - set(re.findall(warning_pattern, old_log)))
assert not new_categories, new_categories
assert not re.search(r'No nets matched|USR-8159 CRITICAL-WARNING|\bERROR:', new_log)
area = (reports / 'lesson3_phy.area').read_text()
resources = {key: int(re.search(r'^#' + name + r'\s+(\d+)', area, re.M).group(1))
    for key, name in [('lut', 'lut'), ('registers', 'reg'), ('bram9k', 'bram'), ('dsp', 'dsp'), ('pll', 'pll')]}
assert resources['pll'] == 2 and resources['bram9k'] == 48 and resources['dsp'] == 11
for file in reports.iterdir():
    if file.is_file() and file.suffix in ('.bit', '.json', '.log', '.ts', '.timing', '.area'):
        shutil.copy2(file, release / file.name)
shutil.copytree(checks, release / 'verification', dirs_exist_ok=True, ignore=shutil.ignore_patterns('work'))
for name in ('check_caption_scroll.py', 'package_caption_scroll.py', 'run_td_caption_scroll.py', 'run_td_caption_scroll.tcl'):
    shutil.copy2(root / 'verification' / name, release / 'verification' / name)
bit = release / 'caption_scroll_hdmi_a.bit'
assert digest(bit) == result['bit_sha256']
metadata = dict(bit=bit.name, snapshot=str(snapshot), backup=str(backup), build=result,
    changed_files=static['changed_files'], resources=resources, previous_resources=old['resources'],
    syntax_errors=0, syntax_warnings=0, new_warning_categories=new_categories,
    inherited_ip_warnings_remain=True, hdmi_port='A', simulation_run=False, hardware_tested=False,
    sd_card_modified=False, previous_bit_preserved=str(previous / 'logic_power_hdmi_a.bit'),
    scope='Scroll all nonempty subtitles by default; one-screen minimum ring prevents short-caption repetition. Preserve UART controls and RAM enables.',
    verification=static, changed_file_sha256={name: digest(root / name) for name in static['changed_files']})
(release / 'release_manifest.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k: metadata[k] for k in ('bit', 'resources', 'previous_resources', 'build')}, indent=2))
