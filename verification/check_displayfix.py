"""Arithmetic/netlist audits only. Does not invoke an RTL simulator."""
from pathlib import Path
import argparse, hashlib, json, re

parser = argparse.ArgumentParser()
parser.add_argument('--gate', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = root/'verification/static_displayfix_20261002'
out.mkdir(exist_ok=True)
clamp = lambda x: max(0, min(255, x))
for gain in range(257):
    for pixel in range(256):
        # Mathematical contrast definition versus the unsigned reformulation.
        expected = clamp(((pixel-128)*gain)//128+128)
        result = clamp((pixel*gain)//128-gain+128)
        assert result == expected, (pixel, gain)
        if gain == 128:
            assert result == pixel

netlist = args.gate.read_text(encoding='utf-8-sig')
mults = re.findall(r'  EG_PHY_MULT18 #\(.*?\)\);', netlist, re.S)
color_mults = [m for m in mults if 'u_video_rgb_contrast' in m]
assert len(color_mults) == 2
# In this release's packed 9x9 primitives, every RGB byte is explicitly
# zero-extended. Thus its sign stays nonnegative with either sign setting.
for channel in ('23:16', '15:8', '7:0'):
    assert any("1'b0,\\u_video_rgb_contrast/rgb ["+channel+']' in m for m in color_mults)
for m in color_mults:
    assert '.MODE("MULT9X9C")' in m
    assert "5'b00000,\\u_scene_caption_overlay/contrast [8:5]" in m
    if 'u_scene_caption_overlay/volume' in m:
        assert '.SIGNEDAMUX("0")' in m
(out/'contrast_dsp_audit.txt').write_text('\n\n'.join(color_mults), encoding='utf-8')

include = root/'src/user_source/hdl_source/audio/audio_view_labels.vh'
words = re.findall(r"audio_label_rom\[(\d+)\] <= 16'h([0-9a-f]{4});", include.read_text())
assert [int(a) for a, _ in words] == list(range(512))
assert any(int(b, 16) for _, b in words[:256])
assert any(int(b, 16) for _, b in words[256:])
result = {
    'contrast_arithmetic_cases': 65792,
    'contrast_arithmetic_equivalent': True,
    'default_contrast_preserves_all_rgb_values': True,
    'mapped_rgb_multiplier_inputs_zero_extended': True,
    'mixed_with_volume_uses_unsigned_a': True,
    'audio_label_rom_bits': 8192,
    'gate_sha256': hashlib.sha256(args.gate.read_bytes()).hexdigest(),
    'simulation_run': False,
    'hardware_tested': False,
    'tearing_status': 'Read/write tail ownership hardened; board confirmation required.'
}
(out/'static_result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
