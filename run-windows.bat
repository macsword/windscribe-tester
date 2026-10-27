@echo off
cd /d "%~dp0"
where pyw >nul 2>&1
if %errorlevel%==0 (
    start "" pyw -3 "%~dp0windscribe_tester.py"
    exit /b 0
)
py -3 "%~dp0windscribe_tester.py"
if errorlevel 1 (
    echo Install Python 3 from https://www.python.org/downloads/ and include Tkinter.
    pause
)
