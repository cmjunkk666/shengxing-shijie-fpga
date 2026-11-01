@echo off
setlocal
set "fpga_panel_python=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\pythonw.exe"
if exist "%fpga_panel_python%" (
    start "" "%fpga_panel_python%" -B -X utf8 "%~dp0tools\display_control_gui.py"
    exit /b 0
)
where pythonw.exe >nul 2>nul
if not errorlevel 1 (
    start "" pythonw.exe -B -X utf8 "%~dp0tools\display_control_gui.py"
    exit /b 0
)
where pyw.exe >nul 2>nul
if not errorlevel 1 (
    start "" pyw.exe -3 -B -X utf8 "%~dp0tools\display_control_gui.py"
    exit /b 0
)
echo Python with Tkinter was not found. Install Python 3 with Tcl/Tk support.
pause
