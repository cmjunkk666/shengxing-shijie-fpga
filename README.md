# 声形视界

**基于安路 EG4S20BG256 的自然声音可视化科普终端。**

通过景物图片、真实自然录音、滚动字幕及声音可视化，让观众“看景物、听声音、观察变化”。FPGA 完成 TF 卡访问、图片缓存、音频播放、波形统计与 HDMI 音视频输出，电脑仅用于可选的字幕和参数配置。

本仓库保存当前可复现工程、配套工具、主题素材和最终固件。视频、参赛报告、海报、历史工程备份和编译中间文件不在上传范围内。

## 已实现功能

- 雷声、鸟鸣、蛙鸣、流水四种自然主题；图片与对应 WAV 音频联动。
- 手动切换、自动轮播、四图选景、音频重播与淡入淡出转场。
- BMP 按比例缩放、亮度与对比度调节、音量调节和屏幕菜单。
- WAVE 短时波形（约 42.7 ms），采用显示增益增强弱信号可读性。
- LEVEL 长时峰值包络（约 6.4 s），用于观察连续起伏、间隔和衰减。
- 默认滚动字幕；Windows 串口工具可修改标题、字幕、亮度、音量及相关显示参数。
- 文字 RAM 和字库 ROM 按需读取，精简未使用的 PLL，以分组极值与移位控制逻辑复杂度。实际整机功耗及节能比例尚未测量。

音频来自卡内 WAV 文件；系统不采集环境声音，也未实现声音识别或 FFT 频谱分析。WAVE 的自适应显示高度不表示不同主题之间的绝对响度。

## 工程目录

| 路径 | 内容 |
| --- | --- |
| `src/td_project/HDMI1.4b_Transmitter_v1.0.al` | TD 工程入口，顶层模块为 `top` |
| `src/user_source/hdl_source/` | 音视频、存储、交互、字幕等 RTL，以及原工程使用的 IP |
| `src/user_source/constraints_source/` | 引脚约束 `pin.adc` 与时序约束 `timing.sdc` |
| `src/user_source/ip_source/`、`src/td_project/al_ip/` | 原工程配套 IP 文件 |
| `tools/` | Windows 串口控制台、字体资源生成、音频准备和素材检查工具 |
| `verification/` | 仿真源文件、检查脚本与 TD 构建入口 |
| `content/声形视界_自然声音主题_大图短版_v4_20260921/` | 当前主题包、卡内文件、素材原件、预览与来源记录 |
| `firmware/caption_scroll_hdmi_a.bit` | 已保留的最终固件，使用 HDMI A |
| `firmware/manifest.json` | 固件 SHA-256、器件、默认状态与构建信息 |
| `doc/convert/` | 图片转换与写卡辅助代码及原使用说明 |

## 硬件与开发环境

- 开发板：HX4S20 系列，目标 FPGA 为 **EG4S20BG256**。
- 音视频输出：**HDMI A**；640×480 视频、48 kHz PCM 音频。
- 存储：FAT32 TF 卡，图片与音频文件位于卡根目录。
- 构建工具：安路 TD，原工程记录版本为 `6.2.168116`。
- 配套脚本：Python 3；串口 GUI 需要 Windows 与 Tkinter。GUI 和素材格式检查使用 Python 标准库；部分图片资源生成工具还需要 Pillow。
- 可选仿真：ModelSim。旧脚本的默认安装路径是 `C:/intelFPGA_pro/20.4/modelsim_ase/win32aloem`，需要按本机安装位置调整。

建议在 Windows 上克隆到较短的路径，例如 `C:\fpga\shengxing-shijie-fpga`。原厂工具及开发板驱动需要自行安装，不包含在仓库中。

## 快速运行

1. 将 `content/声形视界_自然声音主题_大图短版_v4_20260921/card_files/` 中的 4 个 BMP 和 4 个 WAV 文件复制到 FAT32 TF 卡根目录。保留同编号图片与音频文件名的对应关系，不要将整个 `card_files` 文件夹直接复制成卡内子目录。
2. 使用 TD 配套下载工具，将 `firmware/caption_scroll_hdmi_a.bit` 下载到开发板。
3. 将显示设备连接至 **HDMI A**，插入 TF 卡并复位，等待图片加载完成。
4. 默认进入手动模式，显示 LEVEL 长时峰值包络，字幕默认滚动。手动模式下音频播完后静音并保持图片，使用 REPLAY 可再次播放；自动模式在音频结束后等待 5 秒或 10 秒再切图。
5. 用板载按键操作；需要修改字幕时，连接板载 USB-UART 并打开串口控制台。

复制卡内文件之前，可在仓库根目录运行只读格式检查：

```powershell
python tools/check_card_assets.py "content/声形视界_自然声音主题_大图短版_v4_20260921/card_files"
```

这个检查验证文件格式，不检测实际卡的 FAT 类型、物理读取可靠性或上板表现。

## 按键操作

主画面下：

| 操作 | 功能 |
| --- | --- |
| KEY1 短按 | 下一张 |
| KEY2 长按 | 上一张 |
| KEY2 短按 | 切换手动 / 自动模式 |
| KEY1 长按 | 切换自动播放间隔 5 / 10 秒 |
| 两键短按 | 打开 / 关闭设置菜单 |
| 两键长按 | 进入四图浏览 |

四图浏览中，KEY1 短按 / 长按移动选择，KEY2 短按确认并进入手动播放，KEY2 长按返回。设置菜单提供亮度、对比度、音量、WAVE / LEVEL / OFF、字幕与 REPLAY；以屏幕提示为准。

## 串口控制台

双击 `打开串口控制台.cmd`，或运行：

```powershell
python tools/display_control_gui.py
```

选择板载 USB-UART 对应的 COM 端口。参数为 **115200、8N1**。发送前关闭占用同一端口的其他串口软件；工具会等待板端 `K` 确认。

当前工具按用户确认的显示顺序排列：**雷声 → 鸟鸣 → 蛙鸣 → 流水**。这个映射保存在 `tools/display_scene_order.json`，主题 ID 依次为 `4, 1, 2, 3`。重新制作存储卡后，FAT 目录中的发现顺序可能改变，应核对屏幕实际顺序并调整该映射。

标题上限 32 个字符，字幕上限 64 个字符；可用字符以 `tools/glyph_map.json` 为准。串口更改针对 FPGA 叠加文字，不会修改 BMP 图片中已经绘制的文字。运行态配置在复位后恢复默认值。

## 从源码构建

推荐在仓库根目录使用当前构建入口：

```powershell
python verification/run_td_caption_scroll.py --td-exe "D:\anlu\bin\td_commands_prompt.exe"
```

把 `--td-exe` 换成自己的 TD 可执行文件路径。脚本会建立隔离的源码快照，默认将新构建输出写入 `verification/td_final/<时间戳>/verification/td_build/`。该目录包含新生成的 bit、资源和时序结果，不会覆盖仓库中的最终固件。

也可从 TD 打开 `.al` 工程。上传副本仅移除了 `.al` 中绑定原电脑的项目根路径；RTL、引脚约束和时序约束保持原样。部分源文件的相对 `include` 路径以 `src/td_project` 为工作目录，命令行构建脚本已经按此处理。

原工程包含加密 HDMI / SDRAM IP，完整构建依赖安路 TD 支持，不适合直接替换为普通开源综合流程。已有固件在原约束下建立 / 保持时序通过；源码重编译后应重新检查本次生成的时序结果。

最终固件 SHA-256：

```text
362f49e07204b9f4585458bd7e08a704b54be70bce8449fde23dac6bb7a3e356
```

## 验证入口及范围

`verification/README_lesson456.md` 说明了存储、调度、共享链路等验证入口。较新 FAT32 链路使用 `run_storage_tests.py`、`run_schedule_tests.py` 等脚本；旧版 `run_modelsim.py` 和 `run_board_control.py` 针对早期协议，不能作为全部现有功能的验收结果。

部分 `check_*.py` 和 `package_*.py` 是历次修改的差异检查 / 打包脚本，需要本地 `_backup` 或历史编译目录。仓库保留这些代码，但不包含它们引用的历史备份和日志；请勿将缺少历史输入导致的失败误认为当前工程无法构建。准备本次上传时检查了文件完整性、工程引用、Python 语法及卡内素材格式，没有重新运行 FPGA 全量仿真、综合或上板测试。

## 素材与来源

本仓库沿用官方例程及原 IP 的版权标识，不为第三方代码追加新的统一开源许可。自然图片、录音来源与原始许可记录见 [THIRD_PARTY.md](THIRD_PARTY.md) 及主题包的 `source/provenance/`。主题包中的旧 HTML 和 JSON 保留了素材生成时的信息；当前默认状态与固件以本 README 和 `firmware/manifest.json` 为准。
