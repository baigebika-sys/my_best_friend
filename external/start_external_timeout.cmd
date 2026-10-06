@echo off
chcp 65001 >nul
set PYTHONUTF8=1
cd /d "%~dp0"
where py >nul 2>&1
if not errorlevel 1 (
    py -3 bridge.py --delay 40 --task-timeout 35
) else (
    where python >nul 2>&1
    if errorlevel 1 (
        echo Python was not found. Install Python from https://www.python.org/downloads/windows/
        echo Enable "Add python.exe to PATH" during installation.
    ) else (
        python bridge.py --delay 40 --task-timeout 35
    )
)
echo.
echo Bridge stopped. Press any key to close this window.
pause >nul
