@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0zed-classic-context-menu.ps1" %*
set "exitcode=%errorlevel%"
if not "%exitcode%"=="0" (
  echo.
  echo 脚本退出码: %exitcode%
  pause
)
exit /b %exitcode%
