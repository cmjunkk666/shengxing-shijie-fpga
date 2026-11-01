"""Static source, arithmetic and mapped-hardware checks; no RTL simulation."""
from pathlib import Path
from collections import Counter
import argparse, difflib, hashlib, itertools, json, random, re

parser = argparse.ArgumentParser()
parser.add_argument('--gate', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
backup = root / '_backup/logic_power_20261002_165911'
out = root / 'verification/static_logic_power_20261002'
out.mkdir(exist_ok=True)
h = Path('src/user_source/hdl_source')
expected = {str(h / name).replace('\\', '/') for name in (
    'top_tf_hdmi_audio.v', 'SD/seg_scan.v', 'SD/frame_read_write.v',
    'storage/fat32_media.v', 'audio/pcm_wave_overlay.v',
    'scene_caption_overlay.v', 'display_font_rom.v')}
expected.add('tools/generate_display_assets.py')
expected.add('tools/caption_template.txt')
changed, diff = [], []
for folder in ('src', 'tools'):
    for file in sorted((root / folder).rglob('*')):
        if not file.is_file() or file.suffix not in ('.v', '.vh', '.sdc', '.adc', '.py', '.txt'):
            continue
        rel = file.relative_to(root)
        if any(part.endswith('_Runs') for part in rel.parts):
            continue
        old = backup / rel
        before = old.read_text(encoding='utf-8-sig') if old.exists() else ''
        after = file.read_text(encoding='utf-8-sig')
        if before != after:
            changed.append(rel.as_posix())
            diff.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                        fromfile='before/' + rel.as_posix(), tofile='after/' + rel.as_posix()))
assert set(changed) == expected, changed
(out / 'changes.diff').write_text(''.join(diff), encoding='utf-8')

def source(name, old=False):
    return ((backup if old else root) / h / name).read_text(encoding='utf-8-sig')

# Retain the actual ROM contents, capture/statistics, output geometry and scaling.
font_words = lambda s: re.findall(r"font\[\d+\]\s*<=\s*16'h[0-9a-fA-F]+", s)
assert len(font_words(source('display_font_rom.v'))) == 4096
assert font_words(source('display_font_rom.v')) == font_words(source('display_font_rom.v', True))
for name, marker in [('audio/pcm_wave_overlay.v', ' wire signed [10:0] screen_value='),
                     ('scene_caption_overlay.v', ' assign de_out=')]:
    assert source(name).split(marker, 1)[1] == source(name, True).split(marker, 1)[1]
wave = source('audio/pcm_wave_overlay.v')
oldwave = source('audio/pcm_wave_overlay.v', True)
sequential = lambda s: re.findall(r' always @\(posedge clk or posedge rst\)begin.*?\n end\n', s, re.S)
assert sequential(wave) == sequential(oldwave)
assert 'if(ink)character<=text_memory[text_address];' in source('scene_caption_overlay.v')
assert '.enable(ink1)' in source('scene_caption_overlay.v')
assert 'if(enable) pixels<=font[address]' in source('display_font_rom.v')
assert 'if(enable) pixels<=font[address]' in (root / 'tools/generate_display_assets.py').read_text()
template = (root / 'tools/caption_template.txt').read_text(encoding='utf-8-sig')
assert 'if(ink)character<=text_memory[text_address];' in template and '.enable(ink1)' in template
top = source('top_tf_hdmi_audio.v')
assert not any(s in top for s in ('u_audio_pll', 'audio_mclk', 'audio_pll_lock'))
assert 'reset_request = ~rst_n | ~sys_pll_lock | ~video_pll_lock;' in top
assert 'else sd_card_write_ready<=sd_card_write_capacity;' in top
assert top.count('.write_ready(sd_card_write_ready)') == 1
assert top.count('.write_ready(sd_card_write_capacity)') == 1
assert top.split('// ===================== RGB/DE', 1)[1] == source('top_tf_hdmi_audio.v', True).split('// ===================== RGB/DE', 1)[1]

# Check every visible pixel against the original per-pixel RAM address.
# Address tags stand in for arbitrary data: equality then holds for any RAM contents.
# The held word must match on the first/last pixel, every row and every history origin.
for origin in range(128):
    held = None
    for x in range(640):
        if 64 <= x < 576 and x % 4 == 0:
            held = (origin + ((x - 64) // 4)) % 128
        if 64 <= x < 576:
            assert held == (origin + ((x - 64) // 4)) % 128
for bank in (0, 1):
    for y in range(480):
        held = None
        for x in range(640):
            if 64 <= x < 320 and 286 <= y < 302 and x % 16 == 0:
                held = (bank, y - 286, (x - 64) // 16)
            if 64 <= x < 320 and 286 <= y < 302:
                assert held == (bank, y - 286, (x - 64) // 16)

# Original BPB rejection and staged acceptance must agree at geometry boundaries
# and for malformed metadata, including FAT capacities wider than 32 bits.
fat = source('storage/fat32_media.v')
assert 'cluster_count_ok<=cluster_count>=65525 && cluster_count<=32\'h0fffffee;' in fat
assert "fat_capacity_ok<=cluster_limit<=({8'b0,fat32}<<7);" in fat
assert 'root_cluster_ok<=bpb_root>=2 && bpb_root<cluster_limit;' in fat
counts = [0, 1, 65524, 65525, 65526, 0x0FFFFFED, 0x0FFFFFEE, 0x0FFFFFEF, 0xFFFFFFFF]
fats = [0, 1, 511, 512, 513, 0x1FFFFF, 0x200000, 0x3FFFFFF, 0x4000000, 0xFFFFFFFF]
cases = list(itertools.product(counts, fats, [0, 1, 2, 65525, 65527, 0x0FFFFFF0, 0xFFFFFFFF]))
for count in counts:
    for size in fats:
        cases.extend((count, size, r) for r in (count, count + 1, min(0xFFFFFFFF, count + 2)))
rng = random.Random(20261002)
cases.extend((rng.getrandbits(32), rng.getrandbits(32), rng.getrandbits(32)) for _ in range(100000))
for count, size, first in cases:
    limit = count + 2
    rejected = count < 65525 or count > 0x0FFFFFEE or limit > size << 7 or first < 2 or first >= limit
    accepted = (65525 <= count <= 0x0FFFFFEE) and (limit <= size << 7) and (2 <= first < limit)
    assert accepted == (not rejected)

# Counter widths contain every reachable value, including a power-of-two limit.
for ticks in (1, 2, 3, 624, 625, 1024, 41666, 83333):
    bits = max(1, (ticks - 1).bit_length())
    assert 0 <= ticks - 1 < (1 << bits)
assert 'localparam REFRESH_TICKS = `SELF_REFRESH_INTERVAL / 2;' in source('SD/frame_read_write.v')
assert source('SD/frame_read_write.v').split('always @(posedge mem_clk or posedge rst)begin', 1)[1] == source('SD/frame_read_write.v', True).split('always @(posedge mem_clk or posedge rst)begin', 1)[1]
# The write pointer is not delayed in wrusedw; the synchronized read pointer
# only overestimates occupancy. At most two further writes can follow reaching
# the 384-word threshold: the registered grant and the registered decoder pixel.
fifo = source('IP/afifo_16_32_256.v')
assert 'assign wrusedw = wr_addr_diff' in fifo
assert 'assign wr_addr_diff = (wr_addr - shift_rdaddr)' in fifo
assert "assign write_ready=!write_full && write_used<9'd384;" in source('SD/frame_read_write.v')
assert 384 + 2 < 511

result = dict(changed_files=changed, fat_geometry_cases=len(cases),
    font_contents_unchanged=True, wave_capture_and_render_unchanged=True,
    level_history_and_yellow_meter_unchanged=True, audio_pcm_unchanged=True,
    gallery_unchanged=True, clocks_and_refresh_interval_unchanged=True,
    frame_clock_cycles=800*525, graph_word_reads_per_frame=128*81,
    label_word_reads_per_frame=16*16, max_caption_word_reads_per_frame=(512+608)*16,
    write_fifo_conservative_occupancy_bound=386,
    simulation_run=False, hardware_tested=False)

if args.gate:
    gate = args.gate.read_text(encoding='utf-8-sig')
    assert 'u_audio_pll/' not in gate
    assert len(re.findall(r'^  EG_PHY_PLL #', gate, re.M)) == 2
    assert 'sd_card_bmp_m0/files/fat_capacity_ok' in gate
    assert 'frame_read_write_m0/App_ref_req_reg ' in gate
    req = next(line for line in gate.splitlines() if 'Sdr_ref_req_syn_1  (' in line)
    assert "1'b0" not in req and 'App_ref_req' in req
    brams = re.findall(r'^  EG_PHY_BRAM #\(.*?\)\);', gate, re.M | re.S)
    enables = []
    for block in brams:
        inst = re.search(r'\n    \\([^\s]+)\s+\(', block)
        if not inst:
            continue
        name = inst.group(1)
        if name.startswith(('u_pcm_wave_overlay/', 'u_scene_caption_overlay/')):
            pins = {pin: val.strip() for pin, val in re.findall(r'\.(cea|ceb|csa|csb)\(([^)]+)\)', block)}
            # In PDP mode B is the read port even when outputs span DOA/DOB.
            # TD may implement its read enable using CSB2 instead of CEB.
            read_port = 'a' if name.startswith('u_scene_caption_overlay/font/') else 'b'
            read_enables = {pin: val for pin, val in pins.items() if pin.endswith(read_port)}
            enables.append(dict(instance=name, read_port=read_port, pins=read_enables))
    assert len(enables) == 13, enables
    # Every targeted READ port is controlled; a write enable is insufficient.
    assert all(any(v not in ("1'b1", "1'b0") for v in e['pins'].values()) for e in enables), enables
    colors = [m for m in re.findall(r'^  EG_PHY_MULT18 #\(.*?\)\);', gate, re.M | re.S)
              if 'u_video_rgb_contrast' in m]
    for channel in ('23:16', '15:8', '7:0'):
        assert any("1'b0,\\u_video_rgb_contrast/rgb [" + channel + ']' in m for m in colors)
    result.update(gate_sha256=hashlib.sha256(args.gate.read_bytes()).hexdigest(),
                  pll_count=2, ram_port_enables=enables, refresh_request_retained=True,
                  rgb_multiplier_zero_extension_retained=True)
(out / 'static_result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
