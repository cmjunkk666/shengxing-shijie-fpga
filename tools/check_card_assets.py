"""Read-only validation of BMP and optional AUDIO1..4.WAV files for the FPGA.
Usage: python check_card_assets.py E:/
This checks files through the host OS. It does not verify FAT type or on-card chains.
"""
from pathlib import Path
import argparse,struct,sys
ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('directory',type=Path);args=ap.parse_args()
valid=0;bad=0
root_files=[p for p in args.directory.iterdir() if p.is_file()]
files=sorted((p for p in root_files if p.suffix.lower()=='.bmp'),key=lambda p:p.name.casefold())
print('Checking all root BMP files; PC listing order may differ from FAT directory order.')
print('Nature firmware: PIC1.BMP..PIC4.BMP pair with same-number AUDIO WAV even if directory order differs; other BMP names use discovery-slot order.')
if len(files)>4:print('NOTE: FPGA uses the first four eligible directory entries; only four files can be selected per boot.')
for f in files:
 actual_size=f.stat().st_size
 with f.open('rb') as stream:raw=stream.read(54)
 errors=[]
 if len(raw)<54:errors.append('shorter than BMP header')
 else:
  sig,size=struct.unpack_from('<2sI',raw);offset,dib=struct.unpack_from('<II',raw,10)
  width,height,planes,bpp,compression,imagebytes=struct.unpack_from('<iiHHII',raw,18)
  if sig!=b'BM':errors.append('not BM')
  if dib not in (40,108,124):errors.append('unsupported DIB header')
  if not (1<=width<=1920 and 1<=height<=1080) or (planes,bpp,compression)!=(1,24,0):errors.append('requires 1..1920 x 1..1080, positive height, 24-bit BI_RGB')
  pixel_bytes=((max(0,width)*3+3)&~3)*max(0,height)
  if offset<14+dib or offset+pixel_bytes>actual_size:errors.append('invalid offset/truncated pixel array')
  if not offset+pixel_bytes<=size<=actual_size:errors.append('invalid BMP file size')
  if imagebytes not in (0,pixel_bytes):errors.append('invalid image size field')
  if actual_size>8388608:errors.append('file exceeds 8 MiB limit')
 if errors:bad+=1;print(f'{f.name}: INVALID: '+ '; '.join(errors))
 else:valid+=1;print(f'{f.name}: OK ({actual_size} bytes, {width}x{height} RGB888 bottom-up -> aspect-fit 640x480)')
print(f'BMP files checked: {len(files)}; valid: {valid}; invalid: {bad}. FPGA capacity: 4 root BMP entries. Names need not be PIC1..PIC4.')
by_name={p.name.casefold():p for p in root_files}
for slot in range(1,5):
 f=by_name.get(f'audio{slot}.wav')
 if f is None:
  print(f'AUDIO{slot}.WAV: absent; matching PIC{slot}.BMP (or unnamed slot {slot}) uses the built-in tone')
  continue
 try:
  actual_size=f.stat().st_size
  if actual_size>67108864:raise ValueError('exceeds 64 MiB limit')
  with f.open('rb') as stream:
   header=stream.read(12)
   if len(header)!=12 or header[:4]!=b'RIFF' or header[8:]!=b'WAVE':raise ValueError('not RIFF/WAVE')
   riff_end=struct.unpack_from('<I',header,4)[0]+8
   if riff_end>actual_size or riff_end<44:raise ValueError('invalid RIFF length')
   fmt=None;data_size=None
   while stream.tell()+8<=riff_end:
    kind,size=struct.unpack('<4sI',stream.read(8));end=stream.tell()+size+(size&1)
    if end>riff_end:raise ValueError('chunk exceeds RIFF boundary')
    if kind==b'fmt ':
     if size<16 or fmt is not None:raise ValueError('invalid or repeated format chunk')
     fmt=struct.unpack('<HHIIHH',stream.read(16))
     encoding,channels,rate,byte_rate,align,bits=fmt
     if encoding!=1 or channels not in (1,2) or rate!=48000 or bits!=16 or align!=channels*2 or byte_rate!=rate*align:
      raise ValueError('requires PCM16 LE at 48000 Hz, mono/stereo; use prepare_scene_audio.py')
    elif kind==b'data':
     if fmt is None or size==0 or size%fmt[4]:raise ValueError('missing format, empty data or partial sample')
     data_size=size;break
    stream.seek(end)
   if data_size is None:raise ValueError('no data chunk')
   print(f'{f.name}: OK (PIC{slot}.BMP / fallback slot {slot}, {fmt[1]} channel(s), {data_size/fmt[3]:.2f} seconds)')
 except (OSError,ValueError,struct.error) as exc:
  bad+=1;print(f'{f.name}: INVALID: {exc}')
sys.exit(0 if valid and not bad else 1)
