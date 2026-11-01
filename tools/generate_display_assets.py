from pathlib import Path
import json
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parents[1]
hdl=root/'src/user_source/hdl_source'
themes=json.loads((root/'tools/nature_captions.json').read_text(encoding='utf-8'))
assert len(themes)==4
titles=[t['title'] for t in themes]
subtitles=[t['subtitle'] for t in themes]
# Preserve existing wire codes, including all older supported Chinese glyphs.
# New nature glyphs use the previously unused 0..31 and 127 code points.
mapping=json.loads((root/'tools/glyph_map.json').read_text(encoding='utf-8'))
assert len(set(mapping.values()))==len(mapping) and all(0<=v<256 for v in mapping.values())
assert all(mapping[chr(i)]==i for i in range(32,127))
assert all(ch in mapping for text in titles+subtitles for ch in text)
cn=[c for c in mapping if ord(c)>126]
fonts=[ImageFont.truetype('C:/Windows/Fonts/consola.ttf',16),ImageFont.truetype('C:/Windows/Fonts/simsun.ttc',16)]
rows=[0]*4096
preview=Image.new('RGB',(512,256),'#172436');drawp=ImageDraw.Draw(preview)
for ch,code in mapping.items():
    font=fonts[ord(ch)>126];im=Image.new('1',(16,16));d=ImageDraw.Draw(im)
    box=d.textbbox((0,0),ch,font=font)
    # Keep ASCII on a common baseline; Chinese glyphs use the full 16-pixel cell.
    if ord(ch)<=126:d.text((4,-1),ch,font=font,fill=1)
    else:d.text((0,-2),ch,font=font,fill=1)
    for y in range(16):
        rows[code*16+y]=sum((1<<(15-x)) for x in range(16) if im.getpixel((x,y)))
    preview.paste(im.convert('RGB'),((code%32)*16,(code//32)*32))
preview.save(root/'verification/font_preview.png')
mif=['WIDTH=16;','DEPTH=4096;','ADDRESS_RADIX=UNS;','DATA_RADIX=HEX;','CONTENT BEGIN']
mif += [f'{i} : {v:04X};' for i,v in enumerate(rows)]
mif+=['END;']
(hdl/'display_font.mif').write_text('\n'.join(mif)+'\n',encoding='ascii')
body=['// Generated 16x16 synchronous ROM using the TD inference template.',
      'module display_font_rom(input wire clk,enable,input wire [11:0] address,output reg [15:0] pixels);',
      '(* rom_style = "bram" *) reg [15:0] font [0:4095];','initial begin']
body += [f" font[{i}] <= 16'h{v:04x};" for i,v in enumerate(rows)]
body+=['end','always @(posedge clk) if(enable) pixels<=font[address];','endmodule']
(hdl/'display_font_rom.v').write_text('\n'.join(body)+'\n',encoding='ascii')
alltexts=[t for pair in zip(titles,subtitles) for t in pair]
assert all(len(t)<= (32 if i%2==0 else 64) for i,t in enumerate(alltexts))
lengths=sum(len(t)<<(7*i) for i,t in enumerate(alltexts))
func=['function [7:0] default_char;input [8:0] address;begin case(address)']
for i,t in enumerate(alltexts):
    for j,ch in enumerate(t):func.append(f" 9'd{i*64+j}:default_char=8'd{mapping[ch]};")
func+=[' default:default_char=8\'d32;','endcase end endfunction']
template=(root/'tools/caption_template.txt').read_text(encoding='utf-8-sig')
(hdl/'scene_caption_overlay.v').write_text(template.replace('@DEFAULT_LENGTHS@',f"56'h{lengths:014x}").replace('@DEFAULT_CHARS@','\n'.join(func)),encoding='utf-8')
print('Generated glyphs:',len(mapping),'Chinese:',len(cn),'caption lengths:',[len(t) for t in alltexts])
