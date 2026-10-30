@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
    py -3 flasher-builder.py
    if errorlevel 1 pause
    exit /b
)
where python >nul 2>nul
if not errorlevel 1 (
    python flasher-builder.py
    if errorlevel 1 pause
    exit /b
)
echo Install Python 3.10 or newer from python.org, then run: py -3 -m pip install -r requirements.txt
echo Then run this launcher again.
pause
exit /b 1
