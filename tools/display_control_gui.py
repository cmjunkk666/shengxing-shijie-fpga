"""Chinese desktop controls for the existing FPGA display protocol.

Opening this application never opens or writes a serial port. Only an explicit
Send/Apply action does so. Reuses the command-line tool's transport and CRC.
"""
from pathlib import Path
from datetime import datetime
import json
import queue
import re
import threading
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

from display_control import WindowsSerial, packet


def serial_ports():
    import winreg
    found = []
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                            r'HARDWARE\DEVICEMAP\SERIALCOMM') as key:
            index = 0
            while True:
                try:
                    _, value, _ = winreg.EnumValue(key, index)
                except OSError:
                    break
                if re.fullmatch(r'COM\d+', value, re.I):
                    found.append(value.upper())
                index += 1
    except FileNotFoundError:
        pass
    return sorted(set(found), key=lambda name: int(name[3:]))


def level_byte(percent):
    if not 0 <= percent <= 100:
        raise ValueError('亮度和音量必须在 0～100% 之间。')
    return round(percent * 255 / 100)


def load_scene_order():
    """Map each displayed position to its existing UART text target (1..4)."""
    path = Path(__file__).with_name('display_scene_order.json')
    if not path.exists():
        return (1, 2, 3, 4)
    settings = json.loads(path.read_text(encoding='utf-8'))
    order = settings.get('display_order')
    if (not isinstance(order, list) or len(order) != 4 or
            any(type(item) is not int for item in order) or
            set(order) != {1, 2, 3, 4}):
        raise ValueError('图片顺序配置无效：display_order 必须包含 1～4，且不能重复。')
    return tuple(order)


def text_packet(mapping, scene, kind, text):
    if scene not in (1, 2, 3, 4) or kind not in ('title', 'subtitle'):
        raise ValueError('请选择图片 1～4，以及标题或字幕。')
    label, limit = ('标题', 32) if kind == 'title' else ('字幕', 64)
    if len(text) > limit:
        raise ValueError(f'{label}最多 {limit} 个字符，当前 {len(text)} 个。')
    missing = ''.join(dict.fromkeys(c for c in text if c not in mapping))
    if missing:
        raise ValueError(f'板上字库暂不支持这些字符：{missing}\n'
                         '请点击“可用汉字”查看，或先使用英文、数字。')
    command = 0x10 + (scene - 1) * 2 + (kind == 'subtitle')
    return packet(command, bytes(mapping[c] for c in text))


def parameter_packet(brightness, volume, captions, scroll, status, speed):
    if not 1 <= speed <= 16:
        raise ValueError('滚动速度必须在 1～16 之间。')
    flags = int(captions) | (int(scroll) << 1) | (int(status) << 2)
    return packet(0x20, bytes([level_byte(brightness), level_byte(volume), flags, speed]))


def friendly_error(error):
    if isinstance(error, TimeoutError):
        return '未收到开发板确认。请确认串口、板卡供电和最新 bit；观察屏幕后可重新发送。'
    if getattr(error, 'winerror', None) == 5:
        return '串口被占用。请关闭串口助手中的这个端口，再点击发送。'
    if getattr(error, 'winerror', None) in (2, 3):
        return '找不到串口。请连接 CH340 USB 接口，刷新并重新选择端口。'
    if isinstance(error, RuntimeError):
        return '开发板未确认指令：' + str(error)
    return str(error)


class ControlPanel:
    def __init__(self, root, transport=WindowsSerial):
        self.root = root
        self.transport = transport
        self.mapping = json.loads(Path(__file__).with_name('glyph_map.json').read_text(encoding='utf-8'))
        self.results = queue.Queue()
        self.busy = False
        self.actions = []
        self.scene_order = load_scene_order()
        self.scene = tk.StringVar(value=str(self.scene_order[0]))
        self.active_scene = self.scene.get()
        themes = json.loads(Path(__file__).with_name('nature_captions.json').read_text(encoding='utf-8'))
        self.drafts = {str(i): dict(theme) for i, theme in enumerate(themes, 1)}
        self.scene_labels = tuple(f'第 {position} 张 · {themes[scene - 1]["title"]}'
                                  for position, scene in enumerate(self.scene_order, 1))
        self.scene_selection = tk.StringVar(value=self.scene_labels[0])
        self.title = tk.StringVar(value=self.drafts[self.active_scene]['title'])
        self.subtitle = tk.StringVar(value=self.drafts[self.active_scene]['subtitle'])
        self.port = tk.StringVar()
        self.brightness = tk.IntVar(value=100)
        self.volume = tk.IntVar(value=30)
        self.captions = tk.BooleanVar(value=True)
        self.scroll = tk.BooleanVar(value=True)
        self.status = tk.BooleanVar(value=True)
        self.speed = tk.StringVar(value='3')
        self.notice = tk.StringVar(value='尚未发送。面板显示待发送的设置，不能读取开发板当前值。')
        self._build()
        self.refresh_ports()
        self.poll_id = self.root.after(100, self._poll)
        self.root.protocol('WM_DELETE_WINDOW', self.close)

    def _build(self):
        root = self.root
        root.title('FPGA 展示控制台 · 按屏幕顺序')
        root.geometry('990x860')
        root.minsize(880, 800)
        root.configure(bg='#eef3f8')
        style = ttk.Style(root)
        style.theme_use('clam')
        style.configure('.', font=('Microsoft YaHei UI', 10))
        style.configure('TFrame', background='#eef3f8')
        style.configure('TLabel', background='#eef3f8', foreground='#24364b')
        style.configure('TLabelframe', background='#eef3f8')
        style.configure('TLabelframe.Label', background='#eef3f8', foreground='#174b7c', font=('Microsoft YaHei UI', 11, 'bold'))
        style.configure('TButton', padding=(10, 6))
        style.configure('Accent.TButton', foreground='white', background='#1767aa')
        style.map('Accent.TButton', background=[('active', '#12538c'), ('disabled', '#a1b3c5')])
        body = ttk.Frame(root, padding=20)
        body.pack(fill='both', expand=True)
        ttk.Label(body, text='FPGA 展示控制台', font=('Microsoft YaHei UI', 22, 'bold')).pack(anchor='w')
        ttk.Label(body, text='在线修改标题、字幕和播放参数 · 当前 HDMI A 版可直接使用').pack(anchor='w', pady=(3, 12))

        connection = ttk.Frame(body)
        connection.pack(fill='x')
        ttk.Label(connection, text='开发板串口').pack(side='left', padx=(0, 10))
        self.port_box = ttk.Combobox(connection, textvariable=self.port, width=12, state='readonly')
        self.port_box.pack(side='left')
        ttk.Button(connection, text='刷新', command=self.refresh_ports).pack(side='left', padx=8)
        ttk.Label(connection, text='115200 / 8N1    点击发送时自动连接').pack(side='left', padx=8)
        ttk.Button(connection, text='使用说明', command=self.show_help).pack(side='right')
        ttk.Label(body, text='直接发送前，请关闭其他串口软件的同一端口；也可复制指令到你原来的软件发送。', wraplength=880).pack(anchor='w', pady=(7, 9))

        texts = ttk.LabelFrame(body, text='图片文字', padding=12)
        texts.pack(fill='x', pady=(0, 12))
        scene_row = ttk.Frame(texts)
        scene_row.pack(fill='x', pady=(0, 9))
        ttk.Label(scene_row, text='编辑屏幕图片').pack(side='left')
        self.scene_box = ttk.Combobox(scene_row, textvariable=self.scene_selection,
                                      values=self.scene_labels, width=27, state='readonly')
        self.scene_box.pack(side='left', padx=8)
        self.scene_box.bind('<<ComboboxSelected>>', self._change_scene)
        ttk.Label(scene_row, text='序号与主题一起核对').pack(side='left')
        ttk.Button(scene_row, text='可用汉字', command=self.show_glyphs).pack(side='right')
        ttk.Label(texts, text='已按当前卡的播放顺序排列；更换素材后需重新核对。选择这里只改变编辑目标，屏幕切图仍用板上按键。',
                  wraplength=850).pack(anchor='w', pady=(0, 6))
        for kind, label, variable, limit in [('title', '标题', self.title, 32), ('subtitle', '字幕', self.subtitle, 64)]:
            row = ttk.Frame(texts)
            row.pack(fill='x', pady=4)
            ttk.Label(row, text=f'{label}\n最多 {limit} 字', width=10).pack(side='left')
            ttk.Entry(row, textvariable=variable).pack(side='left', fill='x', expand=True, padx=(0, 8))
            self._action(row, f'发送{label}', lambda k=kind: self.submit_text(k), accent=True).pack(side='left', padx=(0, 6))
            ttk.Button(row, text='复制指令', command=lambda k=kind: self.submit_text(k, copy=True)).pack(side='left')
        ttk.Label(texts, text='空文字可清除对应标题或字幕。中文仅支持板上已有字库，英文区分大小写。').pack(anchor='w', pady=(8, 0))

        params = ttk.LabelFrame(body, text='亮度、音量与显示', padding=12)
        params.pack(fill='x', pady=(0, 12))
        levels = ttk.Frame(params)
        levels.pack(fill='x')
        for label, variable in [('亮度 B', self.brightness), ('音量 V', self.volume)]:
            group = ttk.Frame(levels)
            group.pack(side='left', fill='x', expand=True, padx=(0, 12))
            ttk.Label(group, text=label).pack(side='left', padx=(0, 8))
            tk.Scale(group, from_=0, to=100, resolution=1, orient='horizontal', variable=variable,
                     showvalue=False, highlightthickness=0, bg='#eef3f8', troughcolor='#cedbe8',
                     activebackground='#1767aa', sliderlength=22, bd=0).pack(side='left', fill='x', expand=True)
            percentage = ttk.Label(group, width=6, anchor='e')
            percentage.pack(side='left')
            def update_label(*_, v=variable, target=percentage):
                target.configure(text=f'{v.get()}%')
            variable.trace_add('write', update_label)
            update_label()
        options = ttk.Frame(params)
        options.pack(fill='x', pady=(10, 8))
        for label, variable in [('显示标题字幕', self.captions), ('字幕滚动', self.scroll), ('显示状态栏和 B/V', self.status)]:
            ttk.Checkbutton(options, text=label, variable=variable).pack(side='left', padx=(0, 16))
        ttk.Label(options, text='滚动速度').pack(side='left')
        ttk.Combobox(options, textvariable=self.speed, values=tuple(map(str, range(1, 17))), state='readonly', width=4).pack(side='left', padx=6)
        ttk.Label(options, text='1 最快，16 最慢').pack(side='left')
        buttons = ttk.Frame(params)
        buttons.pack(fill='x')
        self._action(buttons, '应用全部设置', self.submit_params, accent=True).pack(side='left', padx=(0, 8))
        self._action(buttons, '静音并应用', self.mute).pack(side='left', padx=(0, 8))
        ttk.Button(buttons, text='复制设置指令', command=lambda: self.submit_params(copy=True)).pack(side='left')
        ttk.Label(params, text='拖动后点击“应用全部设置”。本区设置整组发送；0% 音量为静音，0% 亮度仍保留状态栏。').pack(anchor='w', pady=(8, 0))

        ttk.Label(body, text='复位或重新下载 bit 后，开发板恢复默认设置。电脑停止发送后，FPGA 仍可独立播放。', wraplength=850).pack(side='bottom', anchor='w', pady=(10, 0))
        feedback = ttk.LabelFrame(body, text='发送结果', padding=10)
        feedback.pack(fill='both', expand=True)
        ttk.Label(feedback, textvariable=self.notice, wraplength=870).pack(anchor='w', pady=(0, 5))
        self.log = scrolledtext.ScrolledText(feedback, height=3, wrap='word', font=('Microsoft YaHei UI', 10), state='disabled', bd=0)
        self.log.pack(fill='both', expand=True)

    def _action(self, parent, text, command, accent=False):
        button = ttk.Button(parent, text=text, command=command, style='Accent.TButton' if accent else 'TButton')
        self.actions.append(button)
        return button

    def _change_scene(self, event=None):
        position = self.scene_box.current()
        if not 0 <= position < len(self.scene_order):
            return
        self.drafts[self.active_scene] = {'title': self.title.get(), 'subtitle': self.subtitle.get()}
        self.scene.set(str(self.scene_order[position]))
        self.active_scene = self.scene.get()
        self.title.set(self.drafts[self.active_scene]['title'])
        self.subtitle.set(self.drafts[self.active_scene]['subtitle'])

    def refresh_ports(self):
        try:
            ports = serial_ports()
        except OSError as error:
            self.notice.set('读取串口失败：' + str(error))
            return
        self.port_box.configure(values=ports)
        if self.port.get() not in ports:
            self.port.set(ports[0] if len(ports) == 1 else '')
        if not ports:
            self.notice.set('未发现串口。请连接板载 CH340 的 USB 接口后点击“刷新”。')
        elif len(ports) > 1 and not self.port.get():
            self.notice.set('检测到多个串口，请在设备管理器中确认 CH340 对应的端口。')

    def submit_text(self, kind, copy=False):
        try:
            scene = int(self.scene.get())
            value = self.title.get() if kind == 'title' else self.subtitle.get()
            data = text_packet(self.mapping, scene, kind, value)
            target = self.scene_labels[self.scene_order.index(scene)]
            description = target + ' ' + ('标题' if kind == 'title' else '字幕') + f'：{value or "（清空）"}'
            self.dispatch(data, description, copy)
        except ValueError as error:
            messagebox.showwarning('请检查输入', str(error), parent=self.root)

    def submit_params(self, copy=False):
        try:
            b, v, speed = self.brightness.get(), self.volume.get(), int(self.speed.get())
            data = parameter_packet(b, v, self.captions.get(), self.scroll.get(), self.status.get(), speed)
            switches = '、'.join(label + ('开' if variable.get() else '关') for label, variable in
                                [('字幕', self.captions), ('滚动', self.scroll), ('状态栏', self.status)])
            self.dispatch(data, f'亮度 {b}% / 音量 {v}% / {switches} / 速度 {speed}', copy)
        except (ValueError, tk.TclError) as error:
            messagebox.showwarning('请检查输入', str(error), parent=self.root)

    def mute(self):
        self.volume.set(0)
        self.submit_params()

    def dispatch(self, data, description, copy=False):
        if copy:
            self.root.clipboard_clear()
            self.root.clipboard_append(data.hex(' ').upper())
            self.notice.set('已复制指令，尚未发送。请在串口软件中勾选 HEX 发送并粘贴。')
            self._log('已复制（未发送）：' + description)
            return
        if self.busy:
            return
        port = self.port.get().strip().upper()
        if not re.fullmatch(r'COM\d+', port):
            messagebox.showwarning('请选择串口', '请先选择开发板 CH340 对应的 COM 端口。', parent=self.root)
            return
        self.busy = True
        for button in self.actions:
            button.state(['disabled'])
        self.notice.set(f'正在通过 {port} 发送，等待开发板确认……')
        threading.Thread(target=self._exchange, args=(port, data, description), daemon=True).start()

    def _exchange(self, port, data, description):
        try:
            serial = self.transport(port)
            try:
                serial.exchange(data)
            finally:
                serial.close()
        except Exception as error:
            self.results.put((False, description, friendly_error(error)))
        else:
            self.results.put((True, description, ''))

    def _poll(self):
        try:
            ok, description, error = self.results.get_nowait()
        except queue.Empty:
            pass
        else:
            self.busy = False
            for button in self.actions:
                button.state(['!disabled'])
            if ok:
                self.notice.set('开发板已确认更新（K）。请同时观察屏幕和声音。')
                self._log('确认成功：' + description)
            else:
                self.notice.set('发送未确认。' + error)
                self._log('未确认：' + description + '\n' + error)
        self.poll_id = self.root.after(100, self._poll)

    def _log(self, message):
        self.log.configure(state='normal')
        self.log.insert('end', datetime.now().strftime('%H:%M:%S') + '  ' + message + '\n')
        self.log.see('end')
        self.log.configure(state='disabled')

    def show_glyphs(self):
        window = tk.Toplevel(self.root)
        window.title('板上可用汉字')
        window.geometry('650x330')
        ttk.Label(window, text='支持可打印英文、数字、标点，以及下面这些汉字。可选中复制。', padding=12).pack(anchor='w')
        box = scrolledtext.ScrolledText(window, wrap='char', font=('Microsoft YaHei UI', 15), padx=12, pady=12)
        box.pack(fill='both', expand=True, padx=12, pady=(0, 12))
        box.insert('1.0', ''.join(c for c in self.mapping if ord(c) > 127))
        box.configure(state='disabled')

    def show_help(self):
        messagebox.showinfo('使用说明',
            '1. 开发板加载当前 bit，显示器连接 HDMI A，电脑连接 CH340 USB。\n'
            '2. 选择开发板串口。直接发送前关闭其他软件的同一串口。\n'
            '3. 按屏幕序号和主题选择图片，输入标题/字幕点击发送。\n'
            '   拖动亮度/音量后点击应用全部设置。\n'
            '4. 收到 K 才显示“确认成功”，再观察屏幕与声音。\n\n'
            '使用原串口软件：点击复制指令，在原软件选择 HEX 发送后粘贴；'
            '关闭自动追加换行。收到 4B（K）表示成功，45（E）表示拒绝。\n\n'
            '图片下拉框已按当前卡的屏幕顺序排列；发送时会自动对应正确的主题。\n'
            '更换素材或重拷卡后若播放顺序变化，需重新核对顺序配置。\n'
            '选择图片只决定修改目标，不会切换屏幕图片。空文字会清除对应文字。\n'
            '面板不读取板上参数；开发板复位后恢复默认，需要重新应用设置。', parent=self.root)

    def close(self):
        if self.busy:
            self.notice.set('正在等待串口结果，请稍后关闭。')
            return
        self.root.after_cancel(self.poll_id)
        self.root.destroy()


def main():
    root = tk.Tk()
    try:
        ControlPanel(root)
    except Exception as error:
        root.withdraw()
        messagebox.showerror('控制台启动失败', str(error), parent=root)
        root.destroy()
        raise
    root.mainloop()


if __name__ == '__main__':
    main()
