"""Publish only a checked build; keep earlier firmware and SD assets intact."""
from pathlib import Path
import argparse, difflib, hashlib, json, re, shutil, subprocess, sys

parser = argparse.ArgumentParser()
parser.add_argument('snapshot', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
snapshot = args.snapshot.resolve()
reports = snapshot/'verification/td_build'
release = root/'build_displayfix_20261002'
checks = root/'verification/static_displayfix_20261002'
backup = root/'_backup/displayfix_20261002_150240'
result = json.loads((reports/'build_result.json').read_text())
assert result['bit_generated'] and result['reported_setup_hold_pass']
manifest = json.loads((reports/'source_manifest.json').read_text())
for entry in manifest:
    path = Path(entry['path'])
    if path.suffix == '.prj':
        # The build creates a clean project from the .al source, omitting GUI
        # run state and its absolute project path; the live GUI file stays put.
        project = (root/path.with_suffix('.al')).read_text(encoding='utf-8-sig')
        project = re.sub(r'(<Project\b[^>]*?) Path="[^"]*"', r'\1', project, count=1)
        project = re.sub(r'\s*<Runs>.*?</Runs>', '', project, flags=re.S)
        project = re.sub(r'\s*<Project_Settings>.*?</Project_Settings>', '', project, flags=re.S)
        assert project == (snapshot/path).read_text(encoding='utf-8-sig')
    else:
        assert hashlib.sha256((root/path).read_bytes()).hexdigest() == entry['sha256'], entry['path']
compile_log = (checks/'compile.log').read_text(errors='replace')
assert 'Errors: 0, Warnings: 0' in compile_log
subprocess.run([sys.executable, '-B', str(root/'verification/check_displayfix.py'),
                '--gate', str(reports/'display_gate.v')], check=True)

diff = []
changed = []
for folder in ('src', 'tools'):
    for file in (root/folder).rglob('*'):
        if not file.is_file() or file.suffix not in ('.v', '.vh', '.py'):
            continue
        old = backup/file.relative_to(root)
        if old.exists() and file.read_bytes() == old.read_bytes():
            continue
        changed.append(file.relative_to(root).as_posix())
        diff.extend(difflib.unified_diff(old.read_text(encoding='utf-8-sig').splitlines(True) if old.exists() else [],
                    file.read_text(encoding='utf-8-sig').splitlines(True),
                    fromfile=str(old), tofile=str(file)))
(checks/'changes.diff').write_text(''.join(diff), encoding='utf-8')
for file in reports.iterdir():
    if file.is_file() and file.suffix in ('.bit', '.json', '.log', '.ts', '.timing', '.area'):
        shutil.copy2(file, release/file.name)
shutil.copytree(checks, release/'verification', dirs_exist_ok=True, ignore=shutil.ignore_patterns('work'))
for file in ('check_displayfix.py', 'package_displayfix.py', 'run_td_displayfix.py', 'run_td_displayfix.tcl'):
    shutil.copy2(root/'verification'/file, release/'verification'/file)
area = (reports/'lesson3_phy.area').read_text()
resources = {key: int(re.search(r'^#'+pattern+r'\s+(\d+)', area, re.M).group(1))
             for key, pattern in [('lut', 'lut'), ('registers', 'reg'), ('bram9k', 'bram'), ('dsp', 'dsp')]}
prior_log = (root/'build_nature_captions_20260921/build_console.log').read_text(errors='replace')
new_log = (reports/'build_console.log').read_text(errors='replace')
warning_pattern = r'([A-Z]+-\d+) (?:CRITICAL-)?WARNING'
new_categories = sorted(set(re.findall(warning_pattern, new_log))-set(re.findall(warning_pattern, prior_log)))
assert not new_categories, new_categories
bit = release/'displayfix_hdmi_a.bit'
assert hashlib.sha256(bit.read_bytes()).hexdigest() == result['bit_sha256']
metadata = {
    'bit': bit.name, 'snapshot': str(snapshot), 'backup': str(backup),
    'changed_files': changed, 'build': result, 'resources': resources,
    'syntax_errors': 0, 'syntax_warnings': 0,
    'new_warning_categories': new_categories,
    'inherited_ip_warnings_remain': True,
    'color_fix': 'Unsigned contrast arithmetic avoids mixed-sign DSP packing.',
    'memory_fix': 'Write tail ownership and read-return accounting; board validation pending.',
    'timing_fix': 'FAT32 cluster limit calculated once during mount.',
    'audio_labels': ['音频波形 · 42.7毫秒', '声音强弱 · 近6.4秒'],
    'simulation_run': False, 'hardware_tested': False, 'sd_card_modified': False,
    'previous_bit': 'build_nature_captions_20260921/nature_captions_hdmi_a.bit'
}
(release/'release_manifest.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(metadata, ensure_ascii=False, indent=2))
