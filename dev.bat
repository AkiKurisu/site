@echo off
call .\env\Scripts\activate.bat
start /min cmd /k "mkdocs serve"
:loop
timeout /t 1 >nul
powershell -command "(New-Object System.Net.WebClient).DownloadString('http://127.0.0.1:8000/')"
if %errorlevel% equ 0 (
    start http://127.0.0.1:8000/
    exit
) else (
    goto loop
)
