"""Configure the FPGA display through its onboard CH340 USB port (115200 8N1).

Examples (replace COM5 with the board's port):
  python display_control.py --list-ports
  python display_control.py --port COM5 title 1 "林间鸟鸣"
  python display_control.py --port COM5 subtitle 1 "Welcome to the FPGA exhibition!"
  python display_control.py --port COM5 params --brightness 180 --volume 100
  python display_control.py --port COM5 params --volume 0
  python display_control.py --glyphs

Text changes are volatile and reset to defaults on reset/reconfiguration.
Each parameter command sets ALL parameters; omitted options use defaults shown
by params --help. Volume=0 is FPGA digital mute. Brightness=0 keeps status visible
unless --status off is also specified. Text IDs match PIC1.BMP..PIC4.BMP;
other BMP names retain FAT discovery-slot order (1..4).
No extra Python package is needed on Windows. This utility sends configuration
only: rendering, scrolling, transitions and audio run entirely on the FPGA.
"""
from pathlib import Path
import argparse, ctypes, json, os, time
from ctypes import wintypes


def crc8(data):
    value=0
    for byte in data:
        value ^= byte
        for _ in range(8):
            value=((value<<1)^0x07 if value & 0x80 else value<<1)&255
    return value


def packet(command,payload):
    body=bytes([command,len(payload)])+payload
    return b'\xa5'+body+bytes([crc8(body)])


def list_ports():
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,r'HARDWARE\DEVICEMAP\SERIALCOMM') as key:
            i=0
            while True:
                try:
                    name,value,_=winreg.EnumValue(key,i)
                except OSError:
                    break
                print(f'{value}: {name}')
                i+=1
    except FileNotFoundError:
        print('No serial ports found. Connect the board USB UART port and check its CH340 driver.')


class WindowsSerial:
    def __init__(self,port):
        self.api=ctypes.WinDLL('kernel32',use_last_error=True)
        api=self.api
        signatures={
            'CreateFileW':([wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,ctypes.c_void_p,wintypes.DWORD,wintypes.DWORD,wintypes.HANDLE],wintypes.HANDLE),
            'CloseHandle':([wintypes.HANDLE],wintypes.BOOL),
            'GetCommState':([wintypes.HANDLE,ctypes.c_void_p],wintypes.BOOL),
            'BuildCommDCBW':([wintypes.LPCWSTR,ctypes.c_void_p],wintypes.BOOL),
            'SetCommState':([wintypes.HANDLE,ctypes.c_void_p],wintypes.BOOL),
            'SetCommTimeouts':([wintypes.HANDLE,ctypes.c_void_p],wintypes.BOOL),
            'PurgeComm':([wintypes.HANDLE,wintypes.DWORD],wintypes.BOOL),
            'ReadFile':([wintypes.HANDLE,ctypes.c_void_p,wintypes.DWORD,ctypes.POINTER(wintypes.DWORD),ctypes.c_void_p],wintypes.BOOL),
            'WriteFile':([wintypes.HANDLE,ctypes.c_void_p,wintypes.DWORD,ctypes.POINTER(wintypes.DWORD),ctypes.c_void_p],wintypes.BOOL),
        }
        for name,(args,result) in signatures.items():
            fn=getattr(api,name);fn.argtypes=args;fn.restype=result
        class DCB(ctypes.Structure):
            _fields_=[('length',wintypes.DWORD),('baud',wintypes.DWORD),('flags',wintypes.DWORD),
                      ('reserved',wintypes.WORD),('xonlim',wintypes.WORD),('xofflim',wintypes.WORD),
                      ('bytesize',ctypes.c_ubyte),('parity',ctypes.c_ubyte),('stopbits',ctypes.c_ubyte),
                      ('xonchar',ctypes.c_char),('xoffchar',ctypes.c_char),('errorchar',ctypes.c_char),
                      ('eofchar',ctypes.c_char),('evtchar',ctypes.c_char),('reserved1',wintypes.WORD)]
        self.handle=api.CreateFileW('\\\\.\\'+port,0xc0000000,0,None,3,0,None)
        if self.handle==ctypes.c_void_p(-1).value:
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            dcb=DCB();dcb.length=ctypes.sizeof(DCB)
            self.check(api.GetCommState(self.handle,ctypes.byref(dcb)))
            self.check(api.BuildCommDCBW('baud=115200 parity=N data=8 stop=1 dtr=off rts=off',ctypes.byref(dcb)))
            self.check(api.SetCommState(self.handle,ctypes.byref(dcb)))
            timeouts=(wintypes.DWORD*5)(50,0,2000,0,2000)
            self.check(api.SetCommTimeouts(self.handle,timeouts))
            self.check(api.PurgeComm(self.handle,15))
        except Exception:
            self.close();raise

    @staticmethod
    def check(result):
        if not result:raise ctypes.WinError(ctypes.get_last_error())

    def exchange(self,data):
        written=wintypes.DWORD();buf=ctypes.create_string_buffer(data)
        self.check(self.api.WriteFile(self.handle,buf,len(data),ctypes.byref(written),None))
        if written.value!=len(data):raise TimeoutError('Incomplete serial write')
        received=wintypes.DWORD();reply=ctypes.create_string_buffer(1)
        self.check(self.api.ReadFile(self.handle,reply,1,ctypes.byref(received),None))
        if received.value!=1:raise TimeoutError('No FPGA reply. Check the port and load the display bitstream.')
        if reply.raw!=b'K':raise RuntimeError(f'FPGA rejected command: {reply.raw!r}. Existing configuration was retained.')

    def close(self):
        if self.handle is not None:
            self.api.CloseHandle(self.handle);self.handle=None


def main():
    parser=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--port',help='Board CH340 port, e.g. COM5')
    parser.add_argument('--list-ports',action='store_true')
    parser.add_argument('--glyphs',action='store_true',help='Show all supported characters')
    parser.add_argument('--dry-run',action='store_true',help='Validate and show a packet without sending')
    sub=parser.add_subparsers(dest='operation')
    for name in ['title','subtitle']:
        p=sub.add_parser(name);p.add_argument('scene',type=int,choices=range(1,5));p.add_argument('text')
    p=sub.add_parser('params',help='Set all parameters; each omitted value uses its displayed default')
    p.add_argument('--brightness',type=int,choices=range(256),default=255,metavar='0..255')
    p.add_argument('--volume',type=int,choices=range(256),default=255,metavar='0..255')
    p.add_argument('--captions',choices=['on','off'],default='on')
    p.add_argument('--scroll',choices=['on','off'],default='on')
    p.add_argument('--status',choices=['on','off'],default='on')
    p.add_argument('--speed',type=int,choices=range(1,17),default=3,metavar='1..16',help='Frames per scrolling pixel; smaller is faster (default 3)')
    args=parser.parse_args()
    mapping=json.loads(Path(__file__).with_name('glyph_map.json').read_text(encoding='utf-8'))
    if args.glyphs:print(''.join(mapping));return
    if args.list_ports:list_ports();return
    if not args.operation:parser.error('Choose title, subtitle, params, --glyphs or --list-ports')
    if args.operation=='params':
        flags=(args.captions=='on')|((args.scroll=='on')<<1)|((args.status=='on')<<2)
        data=packet(0x20,bytes([args.brightness,args.volume,flags,args.speed]))
        detail=f'brightness={args.brightness}, volume={args.volume}, captions={args.captions}, scroll={args.scroll}, status={args.status}, frames/pixel={args.speed}'
    else:
        limit=32 if args.operation=='title' else 64
        if len(args.text)>limit:parser.error(f'{args.operation} supports up to {limit} characters')
        missing=''.join(dict.fromkeys(c for c in args.text if c not in mapping))
        if missing:parser.error(f'Characters absent from the compiled font: {missing!r}. Use --glyphs to see supported characters.')
        command=0x10+(args.scene-1)*2+(args.operation=='subtitle')
        data=packet(command,bytes(mapping[c] for c in args.text))
        detail=f'{args.operation} {args.scene}: {args.text!r}'
    if args.dry_run:
        print(detail);print(data.hex(' '));return
    if not args.port:parser.error('--port is required for sending')
    if os.name!='nt':parser.error('This dependency-free serial backend supports Windows only')
    serial=WindowsSerial(args.port)
    try:serial.exchange(data)
    finally:serial.close()
    print(f'FPGA frame commit confirmed: {detail}')


if __name__=='__main__':
    try:main()
    except (OSError,TimeoutError,RuntimeError) as exc:raise SystemExit(str(exc))
