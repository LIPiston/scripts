@echo off
"C:\Users\LIPis\scoop\shims\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0toggle-tun.ps1"
echo.
echo TUN toggle command sent.
ping 127.0.0.1 -n 6 >nul
exit /b
