"""Create a new short nature-audio package; preserve source packs and FPGA firmware."""
from __future__ import annotations

import argparse
import copy
import hashlib
import html
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import wave
import zipfile
from html.parser import HTMLParser
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('sound_base', HERE/'build_sound_content.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
RATE = 48000
PROJECT = Path('C:/Users/23774/Desktop/ANlu/task_one/creating_works/lab_ex5_i2s')
EDITS = [
    dict(intro='林间鸟鸣，留意短促音节。', closing='每次鸣叫的间隔一样吗？',
         source_start=0, source_end=None, repeats=2, repeat_gap=.5, target=(12, 15)),
    dict(intro='池塘蛙鸣，听重复的叫声。', closing='你听出了什么节奏？',
         source_start=0, source_end=10.7, repeats=1, repeat_gap=0, target=(15, 18)),
    dict(intro='山间流水，听连续的水声。', closing='它会像鸟鸣那样停顿吗？',
         source_start=0, source_end=10, repeats=1, repeat_gap=0, target=(15, 18)),
    dict(intro='远处雷声，听低沉的滚动。', closing='雷声的起伏，和流水声一样吗？',
         source_start=0, source_end=None, repeats=1, repeat_gap=0, target=(18, 20)),
]


def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_pcm(path):
    with wave.open(str(path), 'rb') as w:
        assert (w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getcomptype()) == (RATE,1,2,'NONE')
        return np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').copy()


def write_pcm(path, pcm):
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.astype('<i2').tobytes())


def make_audio(root, theme, edit):
    original = read_pcm(root/'source/processed_originals'/f'nature{theme["id"]}.wav')
    start = round(edit['source_start']*RATE)
    end = len(original) if edit['source_end'] is None else round(edit['source_end']*RATE)
    recording = original[start:end].copy()
    # Original clips already have edge fades. Only newly cut boundaries need one.
    edge = round(.02*RATE)
    window = .5-.5*np.cos(np.linspace(0, np.pi, edge))
    if start:
        recording[:edge] = np.rint(recording[:edge]*window).astype('<i2')
    if end < len(original):
        recording[-edge:] = np.rint(recording[-edge:]*window[::-1]).astype('<i2')
    assert np.array_equal(recording[edge:-edge], original[start+edge:end-edge])
    write_pcm(root/'preview'/f'nature{theme["id"]}.wav', recording)

    pieces, timeline = [], []
    cursor = 0

    def add(pcm, label, kind, **extra):
        nonlocal cursor
        timeline.append(dict(start_sample=cursor, end_sample=cursor+len(pcm),
                             start=cursor/RATE, end=(cursor+len(pcm))/RATE,
                             label=label, kind=kind, **extra))
        pieces.append(pcm)
        cursor += len(pcm)

    def silence(seconds):
        add(np.zeros(round(seconds*RATE), dtype='<i2'), '停顿', 'silence')

    def speech(key):
        pcm = np.rint(base.read_voice(root/'source/voice'/f'{theme["id"]}_{key}.wav')*32767).astype('<i2')
        add(pcm, theme[key], 'narration')

    silence(.2)
    speech('intro')
    silence(.3)
    for index in range(edit['repeats']):
        if index:
            silence(edit['repeat_gap'])
        add(recording, '真实自然录音' if not index else '同一鸟鸣录音再次播放', 'recording',
            original_start_seconds=start/RATE, original_end_seconds=end/RATE,
            source_preview=f'source/processed_originals/nature{theme["id"]}.wav')
    silence(.35)
    speech('closing')
    silence(.5)
    full = np.concatenate(pieces)
    duration = len(full)/RATE
    assert edit['target'][0] <= duration <= edit['target'][1], (theme['title'], duration, edit['target'])
    assert np.max(np.abs(full.astype(np.int32))) < 32767
    for segment in timeline:
        if segment['kind'] == 'recording':
            assert np.array_equal(full[segment['start_sample']:segment['end_sample']], recording)
    write_pcm(root/'card_files'/f'AUDIO{theme["id"]}.WAV', full)
    assert np.array_equal(read_pcm(root/'card_files'/f'AUDIO{theme["id"]}.WAV'), full)
    return dict(duration=duration, timeline=timeline, recording_duration=len(recording)/RATE,
                recording_repetitions=edit['repeats'], nature_start_seconds=next(x['start'] for x in timeline if x['kind']=='recording'),
                peak_sample=int(np.max(np.abs(full.astype(np.int32)))), clipping_samples=int(np.sum(np.abs(full.astype(np.int32))>=32767)),
                sample_rate=RATE, channels=1, bits=16,
                original_nature_samples_preserved_except_new_edge_fades=True,
                recording_segments_match_preview=True)


def render_page(root, source, themes):
    text = (source/'主题试听.html').read_text(encoding='utf-8')
    text = text.replace('<title>声形视界 · 科普主题试听</title>', '<title>声形视界 · 自然声音短版试听</title>')
    text = text.replace('先试听原声，再试听含中文讲解的完整版本。', '本页为短版：一句引导、自然录音、一个观察问题。先试听原声，再试听上板版本。')
    text = text.replace('href="../nature_captions_hdmi_a.bit"', 'href="../../build_nature_captions_20260921/nature_captions_hdmi_a.bit"')
    text = text.replace('核对图片主题和语音开头的主题编号', '核对图片主题和语音开头的主题名称')
    text = text.replace('自然声音学习版 · 上板使用', '自然声音短版 · 上板使用')
    text = text.replace('完整上板音频（含讲解）', '短版上板音频（含引导与观察问题）')
    intro = ('<div class="notice"><strong>只需替换四个 WAV</strong><p>当前自然主题图片和 '
             'nature_captions_hdmi_a.bit 可以继续使用。若卡上已有这四张图片，只替换同名 '
             'AUDIO1.WAV～AUDIO4.WAV，安全弹出后插回开发板并复位。'
             '长版素材保留在原目录。手动模式播完保持安静，需要时用 REPLAY 从头重听。</p>'
             '<p>本包没有改变播放速度或音高。鸟鸣为同一段真实短录音播放两遍；蛙鸣和流水缩短片段；'
             '雷声保留原有完整录音和尾声。中文引导仍由本地语音合成生成。</p></div>')
    text = text.replace('<div class="notice"><strong>自然声音短版 · 上板使用</strong>', intro+'\n<div class="notice"><strong>自然声音短版 · 上板使用</strong>', 1)
    article_pattern = re.compile(r'<article\b.*?</article>', re.S)
    articles = article_pattern.findall(text)
    assert len(articles) == 4
    for article, theme in zip(articles, themes):
        updated, n = re.subn(r'<p>\d+\.\d+ 秒 · 中文讲解 \+ 真实自然录音</p>',
            f'<p>{theme["audio"]["duration"]:.1f} 秒 · 中文引导 + 真实自然录音 + 观察问题；自然声音从约 {theme["audio"]["nature_start_seconds"]:.1f} 秒开始</p>', article)
        assert n == 1
        steps = ''.join(
            f'<li><button class="seek" data-time="{seg["start"]:.6f}" data-audio="a{theme["id"]}">{seg["start"]:.1f}s</button>'
            f'<span>{html.escape(seg["label"])}</span></li>'
            for seg in theme['audio']['timeline'] if seg['kind'] != 'silence')
        updated, n = re.subn(r'<details><summary>讲解稿与声音时间点</summary><ol>.*?</ol></details>',
            '<details><summary>短版文稿与声音时间点</summary><ol>'+steps+'</ol></details>', updated, flags=re.S)
        assert n == 1
        text = text.replace(article, updated, 1)
    text = text.replace('本目录适配同目录上一级的自然声音学习版固件；', '本目录适配 nature_captions_hdmi_a.bit；')
    text = text.replace('自然声源：实地录音，经过截取、单声道转换、48 kHz 重采样、固定增益与片段边缘淡化；',
                        '自然声源：此前长版使用的真实录音，保留原有采样、增益和声音特征；短版仅截取片段并对新切口作 20 毫秒淡化；')
    (root/'主题试听.html').write_text(text, encoding='utf-8')
    class Links(HTMLParser):
        def handle_starttag(self, tag, attrs):
            for key, value in attrs:
                if key in ('href', 'src') and value and not value.startswith(('http:', 'https:', '#', 'data:')):
                    assert (root/value).exists(), value
    Links().feed(text)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, default=PROJECT/'build_nature_captions_20260921/content')
    p.add_argument('--output', type=Path, default=PROJECT/'content/声形视界_自然声音主题_短版_v3_20260921')
    p.add_argument('--resume', action='store_true', help='Resume only an incomplete output from this generator.')
    args = p.parse_args()
    source, root = args.source.resolve(), args.output.resolve()
    assert source.is_dir() and source != root
    if root.exists():
        assert args.resume and not (root/'manifest.json').exists() and (root/'source/build_short_nature_content.py').is_file(), 'Output must be new, or an incomplete package from this generator.'
        assert all(sha(root/f'card_files/PIC{i}.BMP')==sha(source/f'card_files/PIC{i}.BMP') for i in range(1,5))
    root.mkdir(parents=True, exist_ok=args.resume)
    for sub in ('card_files', 'preview', 'source/voice', 'source/processed_originals', 'verification'):
        (root/sub).mkdir(parents=True, exist_ok=args.resume)
    source_manifest = json.loads((source/'manifest.json').read_text(encoding='utf-8'))
    source_hashes = {f['file']:sha(source/'card_files'/f['file']) for f in source_manifest['files']}
    for f in source_manifest['files']:
        assert source_hashes[f['file']] == f['sha256']
    for folder in ('originals', 'provenance'):
        shutil.copytree(source/'source'/folder, root/'source'/folder, dirs_exist_ok=args.resume)
    for path in (Path(__file__), HERE/'build_sound_content.py'):
        shutil.copy2(path, root/'source'/path.name)
    for name in ('主题总览.png', '字幕排版预览.png'):
        if (source/name).exists(): shutil.copy2(source/name, root/name)
    old_themes = json.loads((source/'source/themes.json').read_text(encoding='utf-8'))
    themes = copy.deepcopy(old_themes)
    for theme, edit in zip(themes, EDITS):
        theme.update(intro=edit['intro'], closing=edit['closing'], labels=[], short_edit=edit)
        for relative in (f'card_files/PIC{theme["id"]}.BMP', f'preview/theme{theme["id"]}.png'):
            shutil.copy2(source/relative, root/relative)
        shutil.copy2(source/f'preview/nature{theme["id"]}.wav', root/f'source/processed_originals/nature{theme["id"]}.wav')
    base.THEMES = themes
    base.voice_assets(root)
    for theme, edit in zip(themes, EDITS):
        theme['long_version_duration'] = theme['audio']['duration']
        theme['audio'] = make_audio(root, theme, edit)
    dump(root/'source/themes.json', themes)
    render_page(root, source, themes)
    check = subprocess.run([sys.executable, '-B', '-X', 'utf8', str(PROJECT/'tools/check_card_assets.py'), str(root/'card_files')],
                           capture_output=True, text=True, encoding='utf-8')
    (root/'verification/card_assets_check.log').write_text(check.stdout+check.stderr, encoding='utf-8')
    assert check.returncode == 0, check.stdout+check.stderr
    for name, old_hash in source_hashes.items():
        assert sha(source/'card_files'/name) == old_hash
    firmware = PROJECT/'build_nature_captions_20260921/nature_captions_hdmi_a.bit'
    assert sha(firmware) == '9610a63f5f89fd8b5e3219c273195a9c3e3b796d237e211f3ab52a40f91a2d43'
    with zipfile.ZipFile(root/'短版WAV替换包.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted((root/'card_files').glob('*.WAV')):
            z.write(path, path.name)
    files = [dict(file=f.name, bytes=f.stat().st_size, sha256=sha(f)) for f in sorted((root/'card_files').iterdir())]
    manifest = dict(version='nature_sound_short_v3_20260921', source_pack=str(source),
        firmware=str(firmware), firmware_sha256=sha(firmware), files=files,
        rtl_changed=False, firmware_changed=False, card_written=False, hardware_tested=False,
        images_unchanged=all(sha(root/'card_files'/f'PIC{i}.BMP')==source_hashes[f'PIC{i}.BMP'] for i in range(1,5)),
        long_pack_unchanged=True, manual_playback='one shot, then silence; REPLAY restarts',
        autoplay='WAV completion plus 5 or 10 seconds dwell, then next image',
        audio_summary=[dict(id=t['id'], title=t['title'], old_duration=t['long_version_duration'], **t['audio']) for t in themes],
        autoplay_cycle_seconds_excluding_transitions=sum(t['audio']['duration'] for t in themes)+20,
        validation=dict(all_bmp_wav_formats_pass=True, recording_segments_match_preview=True,
                        no_digital_clipping=True, all_preview_links_exist=True, hardware_tested=False,
                        human_audition_pending=True),
        provenance='Real CC0 recordings and separately sourced photos; source credits and license pages retained.',
        limitations=['Not microphone input or FPGA speech recognition.',
                     'Subtitles remain editable observation prompts, not word-synchronized narration.',
                     'Recorded volume is not calibrated natural sound pressure.'],
        preview_sha256=sha(root/'主题试听.html'))
    dump(root/'manifest.json', manifest)
    print(json.dumps(dict(output=str(root), themes=[dict(id=t['id'], title=t['title'],
        seconds=round(t['audio']['duration'],2), nature_starts=round(t['audio']['nature_start_seconds'],2)) for t in themes],
        cycle_seconds=round(manifest['autoplay_cycle_seconds_excluding_transitions'],2)), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
