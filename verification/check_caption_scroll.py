"""Source, circular-address arithmetic and mapped-hardware audits; no RTL simulation."""
from pathlib import Path
import argparse, difflib, hashlib, json, re

parser = argparse.ArgumentParser()
parser.add_argument('--gate', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
backup = root / '_backup/caption_scroll_20261004_190311'
out = root / 'verification/static_caption_scroll_20261004'
out.mkdir(exist_ok=True)
expected = {'src/user_source/hdl_source/scene_caption_overlay.v', 'tools/caption_template.txt'}
changed, diff = [], []
for folder in ('src', 'tools'):
    for f in sorted((root / folder).rglob('*')):
        if not f.is_file() or f.suffix not in ('.v', '.vh', '.sdc', '.adc', '.py', '.txt'):
            continue
        rel = f.relative_to(root)
        if any(part.endswith('_Runs') for part in rel.parts):
            continue
        old = backup / rel
        before = old.read_text(encoding='utf-8-sig') if old.exists() else ''
        after = f.read_text(encoding='utf-8-sig')
        if before != after:
            changed.append(rel.as_posix())
            diff.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                        fromfile='before/' + rel.as_posix(), tofile='after/' + rel.as_posix()))
assert set(changed) == expected, changed
(out / 'changes.diff').write_text(''.join(diff), encoding='utf-8')
src = (root / 'src/user_source/hdl_source/scene_caption_overlay.v').read_text(encoding='utf-8-sig')
template = (root / 'tools/caption_template.txt').read_text(encoding='utf-8-sig')
for text in (src, template):
    assert "scroll_span=sub_length<38?11'd672:({sub_length,4'b0}+11'd64);" in text
    assert '!flags[0] || !flags[1] || sub_length==0 || state==COMMIT' in text
    assert "source_x={1'b0,x}-11'd16+(flags[1]?scroll_offset:11'd0);" in text
    assert 'if(flags[1] && source_x>=scroll_span)source_x=source_x-scroll_span;' in text
    assert 'flags<=7;scroll_frames<=3;' in text
    assert 'if(ink)character<=text_memory[text_address];' in text
    assert '.enable(ink1)' in text
    assert 'sub_length<=38' not in text
assert src.split(' always @* begin\n  panel=', 1)[1] == template.split(' always @* begin\n  panel=', 1)[1]

# Exhaustive address arithmetic for lengths 1..64 and all positions of the ring.
# Reference uses modulo; hardware uses just one subtraction. Verify clipped
# blank cells cannot expose another caption bank and no cell repeats in a row.
pixel_cases = 0
for length in range(1, 65):
    span = max(608, length * 16) + 64
    assert span == (672 if length < 38 else length * 16 + 64)
    for offset in range(span):
        seen = set()
        for x in range(608):
            raw = x + offset
            assert raw < 2048
            actual = raw - span if raw >= span else raw
            assert actual == raw % span
            if actual // 16 < length:
                assert actual < 1024 and actual not in seen
                seen.add(actual)
            pixel_cases += 1
        assert ((offset + 1) if offset + 1 < span else 0) == (offset + 1) % span
    # Scroll disabled: short text appears once, long text clips at the viewport.
    assert sum(1 for x in range(608) if x // 16 < length) == min(608, length * 16)

themes = json.loads((root / 'tools/nature_captions.json').read_text(encoding='utf-8'))
lengths_word = int(re.search(r"lengths<=56'h([0-9a-f]+)", src).group(1), 16)
for i, theme in enumerate(themes):
    n = (lengths_word >> ((2 * i + 1) * 7)) & 127
    assert n == len(theme['subtitle']) == 16

result = dict(changed_files=changed, address_cases=pixel_cases,
    all_lengths_1_to_64_checked=True, default_subtitles_scroll=True,
    default_pixels_per_second=25000000 / 800 / 525 / 3,
    short_caption_period_pixels=672, title_stationary=True,
    uart_protocol_unchanged=True, font_read_enable_retained=True,
    simulation_run=False, hardware_tested=False)
if args.gate:
    gate = args.gate.read_text(encoding='utf-8-sig')
    assert 'u_audio_pll/' not in gate
    assert len(re.findall(r'^  EG_PHY_PLL #', gate, re.M)) == 2
    assert 'frame_read_write_m0/App_ref_req_reg ' in gate
    req = next(line for line in gate.splitlines() if 'Sdr_ref_req_syn_1  (' in line)
    assert "1'b0" not in req and 'App_ref_req' in req
    assert 'u_scene_caption_overlay/scroll_offset' in gate
    brams = re.findall(r'^  EG_PHY_BRAM #\(.*?\)\);', gate, re.M | re.S)
    fonts = [b for b in brams if 'u_scene_caption_overlay/font/' in b]
    assert len(fonts) == 8
    assert all('.cea(\\u_scene_caption_overlay/ink1 ' in b for b in fonts)
    colors = [m for m in re.findall(r'^  EG_PHY_MULT18 #\(.*?\)\);', gate, re.M | re.S)
              if 'u_video_rgb_contrast' in m]
    for channel in ('23:16', '15:8', '7:0'):
        assert any("1'b0,\\u_video_rgb_contrast/rgb [" + channel + ']' in m for m in colors)
    result.update(gate_sha256=hashlib.sha256(args.gate.read_bytes()).hexdigest(),
                  pll_count=2, mapped_font_enable_retained=True,
                  refresh_request_retained=True, rgb_multiplier_zero_extension_retained=True)
(out / 'static_result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
