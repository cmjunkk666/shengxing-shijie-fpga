"""Build offline sound-science content for the existing HDMI A FPGA firmware.

Creates a new local asset package. Does not write cards, serial ports or RTL.
Uses Windows' installed Huihui voice; all example sounds are synthesized here.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import subprocess
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

RATE = 48000
FONT = Path('C:/Windows/Fonts/msyh.ttc')
BOLD = Path('C:/Windows/Fonts/msyhbd.ttc')
BG = '#0c1728'
FG = '#edf4ff'
MUTED = '#b0c1d8'


THEMES = [
    dict(id=1, title='声音强弱', en='AMPLITUDE', color='#64dfb4',
         concept='同一个音高，波形幅度不同，声音强弱也会变化。',
         prompt='试一试：调低板上音量，听声音、看波形高度。',
         question='声音变强时，是波形变高，还是周期变短？',
         answer='本页保持 220 Hz 不变，只改变数字幅度。波形高度改变，周期基本不变。实际听感还受音响和环境影响。',
         intro='主题一，声音强弱。下面三段声音的音高相同，强弱不同。请听声音，并观察波形的高度。',
         labels=['第一段，弱。', '第二段，中等。', '第三段，强。'],
         closing='三段声音的周期相同，幅度逐渐增大。接下来播放持续示例音，你可以调低板上音量，再关掉菜单，观察波形。',
         samples=[dict(name='弱', kind='sine', frequency=220, amplitude=.20, duration=3),
                  dict(name='中', kind='sine', frequency=220, amplitude=.42, duration=3),
                  dict(name='强', kind='sine', frequency=220, amplitude=.72, duration=3)],
         practice=dict(name='调音量练习', kind='sine', frequency=220, amplitude=.72, duration=15)),
    dict(id=2, title='声音高低', en='FREQUENCY', color='#75baff',
         concept='频率越高，同一段时间内的振动次数越多。',
         prompt='比一比：保持音量设置，听音高、看波形疏密。',
         question='音高升高时，同一时间窗口内的周期数怎样变化？',
         answer='150、300、450 Hz 表示每秒振动 150、300、450 次。频率越高，周期越短。本页三个纯音的数字峰值相同，但人耳感到的响度未必相同。',
         intro='主题二，声音高低。请保持板上音量不变，比较下面三个音。频率升高时，留意波形是不是变得更密。',
         labels=['第一段，一百五十赫兹。', '第二段，三百赫兹。', '第三段，四百五十赫兹。'],
         closing='频率升高，周期缩短，同一时间内的振动次数更多。本页数字幅度相同，但你感到的响度不一定相同。',
         samples=[dict(name='150 Hz', kind='sine', frequency=150, amplitude=.60, duration=4),
                  dict(name='300 Hz', kind='sine', frequency=300, amplitude=.60, duration=4),
                  dict(name='450 Hz', kind='sine', frequency=450, amplitude=.60, duration=4)]),
    dict(id=3, title='不同音色', en='TIMBRE', color='#c4a1ff',
         concept='相同基频，加入不同谐波，声音的色彩会改变。',
         prompt='听一听：先听纯音，再听加入谐波的合成音。',
         question='基频相同，为什么两段声音听起来仍然不同？',
         answer='纯音只含 150 Hz；合成音含 150、300、450 Hz。谐波组成改变了波形和音色。两段稳态数字 RMS 均约为 0.32；本示例不代表任何真实乐器，音色也与声音的起落过程有关。',
         intro='主题三，不同音色。下面两段声音的基频都是一百五十赫兹。先听纯音，再听加入谐波的合成音。',
         labels=['第一段，纯音。', '第二段，加入谐波。'],
         closing='两段声音的基频相同，但谐波组成不同，所以波形和音色会变化。这里使用的是合成示例，不是真实乐器录音。',
         samples=[dict(name='纯音', kind='sine', frequency=150, amplitude=.32*math.sqrt(2), duration=5),
                  dict(name='加入谐波', kind='harmonic', frequency=150, rms=.32, duration=5)]),
    dict(id=4, title='生活提示音', en='RHYTHM', color='#ffc779',
         concept='长短、间隔和音高，都可以帮助区分提示音。',
         prompt='猜一猜：慢节奏、快节奏、交替音高有何不同？',
         question='要让两种提示容易区分，除了音量，还能改变什么？',
         answer='可以改变声音持续时间、间隔、节奏或音高组合。本页为原创合成提示音，不对应任何标准警报；波形只显示声音变化，不能代替文字解释提示含义。',
         intro='主题四，生活提示音。下面是三种合成示例，不代表实际警报。请比较它们的节奏和音高。',
         labels=['第一段，慢节奏。', '第二段，快节奏。', '第三段，交替音高。'],
         closing='长短、间隔和音高可以帮助我们区分提示。波形能显示声音变化，但提示的具体含义，还需要文字或约定来说明。',
         samples=[dict(name='慢节奏', kind='slow', amplitude=.60, duration=4),
                  dict(name='快节奏', kind='fast', amplitude=.60, duration=4),
                  dict(name='交替音高', kind='alternating', amplitude=.60, duration=4)])
]


def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def voice_assets(root):
    clips = []
    for t in THEMES:
        for key in ('intro', 'closing'):
            clips.append(dict(id=f'{t["id"]}_{key}', text=t[key]))
        for n, text in enumerate(t['labels']):
            clips.append(dict(id=f'{t["id"]}_label{n}', text=text))
    dump(root/'source'/'speech.json', clips)
    ps = r'''param([Parameter(Mandatory=$true)][string]$AssetRoot)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
    $synth.SelectVoice('Microsoft Huihui Desktop')
    $synth.Rate = 0
    $synth.Volume = 100
    $format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(48000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
    $clips = Get-Content -LiteralPath (Join-Path $AssetRoot 'source/speech.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($clip in $clips) {
        $wavPath = Join-Path $AssetRoot ('source/voice/' + $clip.id + '.wav')
        $synth.SetOutputToWaveFile($wavPath, $format)
        $synth.Speak([string]$clip.text)
        $synth.SetOutputToNull()
    }
} finally { $synth.Dispose() }
Write-Output 'Local Mandarin narration generated.'
'''
    ps_path = root/'source'/'synthesize_voice.ps1'
    ps_path.write_text(ps, encoding='utf-8-sig')
    subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ps_path), '-AssetRoot', str(root)], check=True)


def fade(x, milliseconds=18):
    n = min(round(RATE*milliseconds/1000), len(x)//2)
    if n:
        w = .5-.5*np.cos(np.linspace(0, np.pi, n))
        x = x.copy()
        x[:n] *= w
        x[-n:] *= w[::-1]
    return x


def example(spec):
    count = round(spec['duration']*RATE)
    t = np.arange(count)/RATE
    kind = spec['kind']
    if kind in ('sine', 'harmonic'):
        phase = 2*np.pi*spec['frequency']*t
        x = np.sin(phase)
        if kind == 'harmonic':
            x += .55*np.sin(2*phase)+.30*np.sin(3*phase)
            x *= spec['rms']/np.sqrt((1+.55**2+.30**2)/2)
        else:
            x *= spec['amplitude']
        return fade(x)
    x = np.zeros(count)
    interval, duration = (.95, .32) if kind == 'slow' else ((.38, .15) if kind == 'fast' else (.60, .42))
    for n, start in enumerate(np.arange(0, spec['duration']-duration+1e-5, interval)):
        f = (300 if n%2 == 0 else 450) if kind == 'alternating' else 300
        part = fade(spec['amplitude']*np.sin(2*np.pi*f*np.arange(round(duration*RATE))/RATE))
        left = round(start*RATE)
        x[left:left+len(part)] = part
    return x


def read_voice(path):
    with wave.open(str(path), 'rb') as w:
        assert (w.getframerate(), w.getnchannels(), w.getsampwidth()) == (RATE, 1, 2)
        x = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(np.float64)/32768
    nz = np.flatnonzero(np.abs(x) > .003)
    if len(nz):
        x = x[max(0, nz[0]-round(.10*RATE)):min(len(x), nz[-1]+round(.15*RATE))]
    # Consistent narration peak; examples retain their intentionally different gains.
    peak = float(np.max(np.abs(x))) if len(x) else 0
    if peak:
        x *= .68/peak
    return fade(x, 8)


def make_audio(root, theme):
    pieces, timeline = [], []
    cursor = 0
    def add(x, label, kind, **extra):
        nonlocal cursor
        timeline.append(dict(start=round(cursor/RATE, 4), end=round((cursor+len(x))/RATE, 4), label=label, kind=kind, **extra))
        pieces.append(x)
        cursor += len(x)
    def silence(seconds):
        add(np.zeros(round(seconds*RATE)), '停顿', 'silence')
    def speech(key, text):
        add(read_voice(root/'source'/'voice'/f'{theme["id"]}_{key}.wav'), text, 'narration')
    silence(.55)
    speech('intro', theme['intro'])
    for n, spec in enumerate(theme['samples']):
        silence(.45)
        speech(f'label{n}', theme['labels'][n])
        silence(.45)
        add(example(spec), spec['name'], 'example', spec=spec)
        silence(.55)
    speech('closing', theme['closing'])
    if 'practice' in theme:
        silence(.65)
        add(example(theme['practice']), theme['practice']['name'], 'example', spec=theme['practice'])
    silence(1)
    x = np.concatenate(pieces)
    assert np.max(np.abs(x)) < .99, 'Unexpected clipping'
    pcm = np.rint(x*32767).astype('<i2')
    path = root/'card_files'/f'AUDIO{theme["id"]}.WAV'
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(pcm.tobytes())
    return dict(duration=round(len(x)/RATE, 3), peak=round(float(np.max(np.abs(x))), 6), timeline=timeline)


def make_image(root, theme):
    scale = 3
    im = Image.new('RGB', (640*scale, 480*scale), BG)
    d = ImageDraw.Draw(im)
    def box(coords, fill, outline=None, radius=0):
        xy = tuple(round(c*scale) for c in coords)
        if radius:
            d.rounded_rectangle(xy, radius*scale, fill=fill, outline=outline, width=scale)
        else:
            d.rectangle(xy, fill=fill, outline=outline, width=scale)
    def text(x, y, content, size, color=FG, bold=False, max_width=592):
        f = ImageFont.truetype(str(BOLD if bold else FONT), size*scale)
        assert d.textlength(content, font=f) <= max_width*scale, f'Text overflow: {content}'
        d.text((x*scale, y*scale), content, font=f, fill=color, anchor='lt')
    def line(points, color, width=1):
        d.line([(round(x*scale), round(y*scale)) for x,y in points], fill=color, width=width*scale)
    accent = theme['color']
    # Reserved: status y8..72, title y88..120, live waveform y286..400,
    # subtitle y424..456 and key hints y464..479. No curriculum text lies there.
    box((0, 0, 639, 74), '#101e33')
    text(174, 78, '声形视界  /  SOUND LAB', 15, MUTED)
    text(28, 127, f'{theme["id"]:02d}', 33, accent, True)
    text(91, 127, theme['title'], 33, FG, True)
    text(29, 173, theme['concept'], 18, MUTED)
    text(538, 201, '原理示意', 12, MUTED, max_width=80)
    panels = len(theme['samples'])
    gap, left, total = 12, 28, 584
    width = (total-gap*(panels-1))/panels
    for n, spec in enumerate(theme['samples']):
        x0 = left+n*(width+gap)
        box((x0, 218, x0+width, 277), '#17283e', '#2a405b', 8)
        text(x0+12, 224, spec['name'], 15, accent, True, width-24)
        t = np.linspace(0, 1, 300)
        if theme['id'] == 1:
            y = np.sin(t*4*np.pi)*spec['amplitude']/.72
        elif theme['id'] == 2:
            y = np.sin(t*4*np.pi*(spec['frequency']/150))
        elif theme['id'] == 3:
            y = np.sin(t*4*np.pi)
            if spec['kind'] == 'harmonic':
                y += .55*np.sin(t*8*np.pi)+.30*np.sin(t*12*np.pi)
            y /= np.max(np.abs(y))
        else:
            pulses = 3 if n == 0 else (6 if n == 1 else 4)
            y = np.where((t*pulses)%1 < .42, .8, -.15)
            if n == 2:
                # Equal height, alternating cycle density: pitch is not amplitude.
                phase_in_burst=(t*pulses)%1
                cycles=np.where((t*pulses).astype(int)%2 == 0, 2, 3)
                y=np.where(phase_in_burst < .72, .85*np.sin(phase_in_burst/.72*cycles*2*np.pi), 0)
        line([(x0+12, 259), (x0+width-12, 259)], '#3b5069')
        line(zip(x0+12+t*(width-24), 259-y*11), accent, 2)
    # Empty area is intentionally filled by the FPGA's real PCM waveform overlay.
    box((60, 284, 580, 401), '#0a1422', radius=8)
    text(28, 406, theme['prompt'], 16, FG)
    output = im.resize((640,480), Image.Resampling.LANCZOS)
    output.save(root/'card_files'/f'PIC{theme["id"]}.BMP')
    output.save(root/'preview'/f'theme{theme["id"]}.png')
    return output


def build_preview(root, themes, images):
    sheet = Image.new('RGB', (1320, 1062), '#e9eef5')
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(str(BOLD), 25)
    d.text((20,14), '声形视界 · 首版科普主题素材', font=f, fill='#182c45')
    for n, im in enumerate(images):
        sheet.paste(im, (12+(n%2)*656, 64+(n//2)*494))
    sheet.save(root/'主题总览.png')
    cards = []
    for t in themes:
        timeline = ''.join(f'<li><button class="seek" data-time="{seg["start"]}" data-audio="a{t["id"]}">{seg["start"]:.1f}s</button><span>{html.escape(seg["label"])}</span></li>'
                           for seg in t['audio']['timeline'] if seg['kind'] != 'silence')
        cards.append(f'''<article style="--accent:{t['color']}"><div class="chapter">TOPIC {t['id']:02d} / {t['en']}</div>
<h2>{t['title']}</h2><p class="lead">{t['concept']}</p>
<img src="preview/theme{t['id']}.png" alt="{t['title']}，开发板图片预览" width="640" height="480">
<p class="caption">图片中的空白区域为板上状态、字幕和实时波形留位。此处是素材预览。</p>
<audio id="a{t['id']}" controls preload="metadata" src="card_files/AUDIO{t['id']}.WAV"></audio>
<p>{t['audio']['duration']:.1f} 秒 · 中文讲解 + 对比声音{' + 15 秒音量练习' if t['id']==1 else ''}</p>
<div class="question"><strong>想一想</strong><p>{t['question']}</p><details><summary>查看解释</summary><p>{t['answer']}</p></details></div>
<details><summary>讲解稿与声音时间点</summary><ol>{timeline}</ol></details></article>''')
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>声形视界 · 科普主题试听</title><style>
*{box-sizing:border-box}body{margin:0;background:#091322;color:#edf4ff;font:16px/1.8 "Microsoft YaHei",sans-serif}
main{max-width:1380px;margin:auto;padding:40px 24px}header{max-width:950px;margin-bottom:28px}.tag{letter-spacing:3px;color:#70dfba;font-size:13px}h1{font-size:38px;margin:6px 0 16px;line-height:1.4}h2{margin:2px 0;font-size:29px}.intro{color:#c0cede}
.notice{background:#17253a;border:1px solid #344b66;padding:18px 24px;border-radius:14px;margin:24px 0 32px}.notice p{margin:6px 0}.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}article{background:#101e32;border:1px solid #293d56;border-top:3px solid var(--accent);padding:24px;border-radius:16px;min-width:0}.chapter{font-size:12px;color:var(--accent);letter-spacing:2px}.lead{color:#c0cede;min-height:56px}img{display:block;width:100%;height:auto;border-radius:10px;border:1px solid #34465f}audio{width:100%;margin-top:12px}.caption{font-size:13px;color:#9eafc6}.question{background:#182b43;border-radius:10px;padding:16px 18px;margin:20px 0}.question p{margin:6px 0}summary{cursor:pointer;color:#b4d9ff}ol{padding-left:22px}li{margin:10px 0}.seek{background:#254565;color:white;border:0;padding:4px 10px;border-radius:6px;margin-right:10px;cursor:pointer}footer{color:#9eb0c8;font-size:14px;margin-top:30px}a{color:#91cfff}@media(max-width:900px){.grid{grid-template-columns:1fr}h1{font-size:28px}main{padding:22px 14px}article{padding:18px}}
</style><main><header><div class="tag">声形视界 / SOUND LAB</div><h1>听到变化，也看见变化。</h1><p class="intro">四个循序渐进的声音科普主题。先在电脑上试听和审阅，再将配套素材用于开发板测试。每页包含知识说明、对比声音和一个观察问题。</p></header>
<div class="notice"><strong>首次上板使用</strong>
<p>① 备份原卡内容，将 <a href="card_files/">card_files</a> 内 4 张 BMP 和 4 个 WAV 放入卡根目录；根目录只保留四张待测 BMP。尽量按 PIC1～PIC4 顺序逐个复制。</p>
<p>② 使用 course_complete_hdmi_a.bit，HDMI 接 A。等待 CACHE 4/4，关闭自动轮播后试听完整讲解。</p>
<p>③ 在现有串口控制台取消“显示标题字幕”，保留“显示状态栏和 B/V”，核对亮度与音量后点击“应用全部设置”。这会整组发送参数，复位后需要重设。图片已包含新的中文说明。</p>
<p>④ 核对图片主题编号与语音开头的“主题一／二／三／四”一致。当前固件按 FAT 目录顺序分配 PIC，文件名并不保证顺序；若错配，按 source/rebind_audio.py 的帮助，在电脑上生成对应顺序的音频，再由你复制到卡。</p>
<p>⑤ 当前一段 WAV 播完后会回到内置提示音；切到另一页再返回可重播。主题一末尾有 15 秒持续音，供板上音量实验使用。</p></div>
<section class="grid">''' + ''.join(cards) + '''</section><footer><p>声音素材：本地程序原创合成。中文讲解：Windows Microsoft Huihui Desktop 合成语音，后续可替换为真人录音。静态小图标为原理示意；板上动态波形来自实际输出的 PCM，不采集环境声音，也不表示声压分贝。</p><p>本包仅准备内容，未修改 RTL、烧录硬件或写入存储卡。图片均为 640×480 RGB24 BMP；音频为 48 kHz、16 位、单声道 PCM WAV。缩放边界测试请继续使用之前的异尺寸测试图。</p></footer></main>
<script>const players=[...document.querySelectorAll('audio')];for(const a of players)a.addEventListener('play',()=>players.filter(b=>b!==a).forEach(b=>b.pause()));for(const b of document.querySelectorAll('.seek'))b.addEventListener('click',()=>{const a=document.getElementById(b.dataset.audio);const go=()=>{a.currentTime=Number(b.dataset.time);a.play().catch(()=>{});};if(a.readyState>=1)go();else{a.addEventListener('loadedmetadata',go,{once:true});a.load();}});</script></html>'''
    (root/'主题试听.html').write_text(page, encoding='utf-8')


REBIND = '''"""Reorder WAV files into a NEW local folder. Never writes to the card.
Example: screen PIC1..4 show themes 3,1,4,2:
  python rebind_audio.py --order 3142 --output C:/Users/23774/Desktop/rebound_audio
"""
import argparse, shutil
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--order',required=True,help='Theme numbers seen on screen PIC1..4, e.g. 3142')
p.add_argument('--output',required=True,type=Path,help='A new local directory, not the SD card')
a=p.parse_args()
if len(a.order)!=4 or set(a.order)!=set('1234'):p.error('--order must be a permutation of 1234')
source=Path(__file__).resolve().parents[1]/'card_files'
target=a.output.resolve()
if target.drive.casefold()!=source.drive.casefold():p.error('Use a local directory on the same drive as this package; copy to the card manually afterwards')
target.mkdir(parents=True,exist_ok=False)
for slot,topic in enumerate(a.order,1):
    shutil.copy2(source/f'AUDIO{topic}.WAV',target/f'AUDIO{slot}.WAV')
print(f'Generated WAV order {a.order}: {target}. Card was not accessed.')
'''


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args()
    root=args.output.resolve()
    root.mkdir(parents=True,exist_ok=False)
    for name in ('card_files','preview','source/voice'):
        (root/name).mkdir(parents=True)
    (root/'source'/'build_sound_content.py').write_bytes(Path(__file__).read_bytes())
    (root/'source'/'rebind_audio.py').write_text(REBIND,encoding='utf-8')
    voice_assets(root)
    images=[]
    themes=[]
    for theme in THEMES:
        images.append(make_image(root,theme))
        item=dict(theme)
        item['audio']=make_audio(root,theme)
        themes.append(item)
    dump(root/'source'/'themes.json',themes)
    build_preview(root,themes,images)
    checks=[]
    for path in sorted((root/'card_files').iterdir()):
        checks.append(dict(file=path.name,bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    dump(root/'manifest.json',dict(version='sound_lab_content_v1',date='2026-09-21',firmware='course_complete_hdmi_a.bit',
          voice='Microsoft Huihui Desktop, local synthesized Mandarin',audio_source='original procedural synthesis',
          bmp='640x480 RGB24 positive-height BI_RGB',wav='48000 Hz PCM16 mono',files=checks,
          card_written=False,rtl_changed=False,hardware_tested=False,
          notes=['Disable autoplay for complete narration.', 'Hide old FPGA title/subtitle overlays with existing serial GUI.',
                 'Theme IDs must be checked against screen PIC order; FAT discovery order is not filename order.',
                 'Firmware returns to tone at WAV EOF.', 'All four images are 640x480; separate resize test assets are unchanged.']))
    print(json.dumps(dict(output=str(root),topics=[dict(id=t['id'],title=t['title'],seconds=t['audio']['duration']) for t in themes]),ensure_ascii=False,indent=2))


if __name__=='__main__':main()
