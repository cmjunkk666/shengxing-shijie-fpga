"""Enlarge the four nature photos while preserving firmware overlay regions."""
from pathlib import Path
from html.parser import HTMLParser
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFont, ImageOps

PROJECT = Path('C:/Users/23774/Desktop/ANlu/task_one/creating_works/lab_ex5_i2s')
BRIEF_LINES = [
    ['听短促的音节', '观察音节停顿', '比较鸣叫间隔'],
    ['辨认重复叫声', '听叫声的节奏', '观察强弱变化'],
    ['听连续流水声', '分辨细碎变化', '观察持续起伏'],
    ['听低沉滚动声', '观察突然增强', '留意余声衰减'],
]


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def dump(p, data):
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def make_image(root, theme):
    scale = 3
    original = Image.open(root/f'card_files/PIC{theme["id"]}.BMP').convert('RGB')
    canvas = Image.new('RGB', (640*scale, 480*scale), '#0b1725')
    d = ImageDraw.Draw(canvas)
    photo = ImageOps.exif_transpose(Image.open(root/'source/originals'/theme['photo_file'])).convert('RGB')
    if theme.get('photo_crop'):
        photo = photo.crop(theme['photo_crop'])
    photo = ImageOps.fit(photo, (440*scale, 200*scale), Image.Resampling.LANCZOS)
    mask = Image.new('L', photo.size)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,photo.width-1,photo.height-1), radius=12*scale, fill=255)
    canvas.paste(photo, (16*scale, 80*scale), mask)
    boxes = []

    def text(x, y, value, size, color='#edf5ff', bold=False, width=152):
        font = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc' if bold else 'C:/Windows/Fonts/msyh.ttc', size*scale)
        bounds = d.textbbox((x*scale,y*scale), value, font=font, anchor='lt')
        assert d.textlength(value,font=font) <= width*scale, value
        assert bounds[2] <= 632*scale and bounds[3] <= 280*scale, (value,bounds)
        d.text((x*scale,y*scale), value, font=font, anchor='lt', fill=color)
        boxes.append({'text':value,'box':[v/scale for v in bounds]})

    text(472,83,f'{theme["id"]:02d} / 自然声景',12,'#aebed2')
    text(472,116,theme['title'],26,bold=True)
    feature = theme['feature'].split(' · ')
    assert len(feature) == 2
    for n, line in enumerate(feature):
        text(472,159+n*21,line,16,theme['color'],bold=True)
    for n, line in enumerate(BRIEF_LINES[theme['id']-1]):
        text(479,211+n*23,line,15,width=145)
        d.ellipse((468*scale,(218+n*23)*scale,472*scale,(222+n*23)*scale), fill=theme['color'])
    d.rounded_rectangle((25*scale,250*scale,176*scale,273*scale),radius=5*scale,fill='#122334')
    text(34,254,theme['photo_note'],12,'#d5e1f1',width=140)
    # Replace only the photo/text strip. Status, waveform, question and caption
    # areas retain the previous exact RGB values; no extra resampling of them.
    strip = canvas.crop((0,74*scale,640*scale,284*scale)).resize((640,210),Image.Resampling.LANCZOS)
    result = original.copy()
    result.paste(strip,(0,74))
    assert result.crop((0,0,640,74)).tobytes()==original.crop((0,0,640,74)).tobytes()
    assert result.crop((0,284,640,480)).tobytes()==original.crop((0,284,640,480)).tobytes()
    result.save(root/f'card_files/PIC{theme["id"]}.BMP')
    result.save(root/f'preview/theme{theme["id"]}.png')
    theme['layout'] = {'photo_box':[16,80,456,280], 'right_column_brief_lines':BRIEF_LINES[theme['id']-1],
                       'text_boxes':boxes,'firmware_overlay_regions_unchanged':True}
    return original, result


def caption_preview(root, images):
    mapping = json.loads((PROJECT/'tools/glyph_map.json').read_text(encoding='utf-8'))
    captions = json.loads((PROJECT/'tools/nature_captions.json').read_text(encoding='utf-8'))
    rows = {int(a):int(v,16) for a,v in re.findall(r"font\[(\d+)\] <= 16'h([0-9a-f]+);",(PROJECT/'src/user_source/hdl_source/display_font_rom.v').read_text())}
    sheet = Image.new('RGB',(1280,1000),'#091322')
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16)
    ImageDraw.Draw(sheet).text((16,9),'大图版字幕排版预览（非上板截图；声音图由开发板实时绘制）',font=font,fill='#d7e3f2')
    for i,(original,captions_for_scene) in enumerate(zip(images,captions)):
        pic=original.copy()
        pixels=pic.load()
        for kind,text in captions_for_scene.items():
            y0,y1,baseline=(422,442,424) if kind=='title' else (442,462,444)
            for y in range(y0,y1):
                for x in range(8,632): pixels[x,y]=tuple(v>>2 for v in pixels[x,y])
            for c,ch in enumerate(text):
                for y in range(16):
                    bits=rows[mapping[ch]*16+y]
                    for x in range(16):
                        if bits & (1<<(15-x)):pixels[16+c*16+x,baseline+y]=(243,248,255)
        sheet.paste(pic,((i%2)*640,40+(i//2)*480))
    sheet.save(root/'字幕排版预览.png')


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source',type=Path,default=PROJECT/'content/声形视界_自然声音主题_短版_v3_20260921')
    ap.add_argument('--output',type=Path,default=PROJECT/'content/声形视界_自然声音主题_大图短版_v4_20260921')
    args=ap.parse_args()
    src,root=args.source.resolve(),args.output.resolve()
    assert src.is_dir() and not root.exists()
    source_hashes={p.name:sha(p) for p in (src/'card_files').iterdir()}
    shutil.copytree(src,root)
    shutil.copy2(Path(__file__),root/'source'/Path(__file__).name)
    themes=json.loads((src/'source/themes.json').read_text(encoding='utf-8'))
    old_images,images=[],[]
    for t in themes:
        before,after=make_image(root,t)
        old_images.append(before);images.append(after)
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
    sheet=Image.new('RGB',(1320,1052),'#101e31');d=ImageDraw.Draw(sheet)
    d.text((16,14),'声形视界 · 大图短版 / 景物照片面积增加约 34%',font=font,fill='#edf5ff')
    for i,pic in enumerate(images):sheet.paste(pic,(12+(i%2)*656,58+(i//2)*490))
    sheet.save(root/'主题总览.png')
    comparison=Image.new('RGB',(1280,530),'#101e31');d=ImageDraw.Draw(comparison)
    d.text((16,10),'原版：照片 328 × 200',font=font,fill='#9baec5')
    d.text((656,10),'大图版：照片 440 × 200',font=font,fill='#71dfbd')
    comparison.paste(old_images[0],(0,50));comparison.paste(images[0],(640,50))
    comparison.save(root/'图片放大前后对比.png')
    caption_preview(root,images)
    dump(root/'source/themes.json',themes)

    page=root/'主题试听.html'
    text=page.read_text(encoding='utf-8')
    text=text.replace('声形视界 · 自然声音短版试听','声形视界 · 大图短版试听')
    text=text.replace('本页为短版：一句引导、自然录音、一个观察问题。','本页为大图短版：景物照片面积增加约 34%，配合一句引导、自然录音和一个观察问题。')
    text=text.replace('<strong>只需替换四个 WAV</strong>', '<strong>大图版：只需替换四张 BMP</strong>')
    text=text.replace('当前自然主题图片和 nature_captions_hdmi_a.bit 可以继续使用。若卡上已有这四张图片，只替换同名 AUDIO1.WAV～AUDIO4.WAV，安全弹出后插回开发板并复位。长版素材保留在原目录。',
        '当前短版 WAV 和 nature_captions_hdmi_a.bit 可以继续使用。将本包的 PIC1.BMP～PIC4.BMP 替换到卡根目录；若尚未使用短版音频，则同时复制本包四个 WAV。安全弹出后插回开发板并复位。旧图片及长版、短版音频均保留在原目录。')
    text=text.replace('照片中的闪电只是天气场景示意，不代表与声音精确同步的那次闪电。','照片展示雷暴天气场景，与录音并非同一次采集。')
    # Expose the comparison above the existing interactive audition cards.
    text=text.replace('<section class="grid">','<p class="caption"><a href="图片放大前后对比.png">查看照片放大前后对比</a> · <a href="大图BMP替换包.zip">下载四张 BMP 替换包</a></p>\n<section class="grid">',1)
    page.write_text(text,encoding='utf-8')
    with zipfile.ZipFile(root/'大图BMP替换包.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted((root/'card_files').glob('*.BMP')):z.write(p,p.name)
    with zipfile.ZipFile(root/'大图BMP替换包.zip') as z:
        assert z.testzip() is None
        for name in z.namelist():assert z.read(name)==(root/'card_files'/name).read_bytes()
    class Links(HTMLParser):
        def handle_starttag(self,tag,attrs):
            for k,v in attrs:
                if k in ('href','src') and v and not v.startswith(('http:','https:','#','data:')):
                    assert (root/v).exists(),v
    Links().feed(text)
    check=subprocess.run([sys.executable,'-B','-X','utf8',str(PROJECT/'tools/check_card_assets.py'),str(root/'card_files')],capture_output=True,text=True,encoding='utf-8')
    (root/'verification/card_assets_check.log').write_text(check.stdout+check.stderr,encoding='utf-8')
    assert check.returncode==0,check.stdout+check.stderr
    for name,digest in source_hashes.items():assert sha(src/'card_files'/name)==digest
    assert all(sha(root/f'card_files/AUDIO{i}.WAV')==source_hashes[f'AUDIO{i}.WAV'] for i in range(1,5))
    manifest=json.loads((src/'manifest.json').read_text(encoding='utf-8'))
    manifest.update(version='nature_sound_large_short_v4_20260921',source_pack=str(src),images_unchanged=False,
        short_audio_unchanged=True,previous_pack_unchanged=True,
        files=[dict(file=p.name,bytes=p.stat().st_size,sha256=sha(p)) for p in sorted((root/'card_files').iterdir())],
        image_layout=dict(previous_photo_size=[328,200],photo_size=[440,200],area_increase_percent=round((440/328-1)*100,2),
                          changed_region=[0,74,640,284],outside_region_pixels_unchanged=True),preview_sha256=sha(page))
    dump(root/'manifest.json',manifest)
    print(json.dumps({'output':str(root),'photo_area_increase_percent':manifest['image_layout']['area_increase_percent'],
        'all_file_formats_passed':True,'short_audio_unchanged':True,'hardware_tested':False},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
