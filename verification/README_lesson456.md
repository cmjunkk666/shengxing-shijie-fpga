# 第4～6课验证入口

运行 `python run_all_456.py` 复现当前软件检查；运行 `python run_td_lesson3.py` 生成隔离的 TD 快照。后者是沿用的构建脚本名，实际编译当前 `src`，并非第三课旧代码。

- `run_storage_tests.py`：实际 SPI 引脚协议、CRC 重试、FAT32 与完整 BMP 像素。
- `run_schedule_tests.py`：协议替身隔离调度器，覆盖缺图、源错误、上下张与轮播；不作为完整存储链路证据。
- `run_shared_regression.py`：保留音频、按键、帧呈现、写地址和像素流水线的有效回归。
- `run_aux_tests.py`：真实 FIFO 中止与复位、OSD 像素和预览。
- `run_cache_tests.py 0`：真实 FAT32/BMP、读写 FIFO、40 MHz 内存仲裁、25 MHz 视频与呈现握手；以扇区模型代替 SPI、以八周期返回模型代替加密 SDRAM 控制器。逐像素运行约需 10～20 分钟。

`run_modelsim.py`、`run_board_control.py` 等旧控制器测试针对原始扇区扫描协议，仅作历史资料；不要把它们作为新版 FAT32 的验收入口。

交付时的日志另外保存在 `results_lesson456_20260915`，不会依赖临时工作目录。测试缩短的毫秒计数和扇区等待不能用于宣称真实启动耗时。
