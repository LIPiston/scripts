

REM 作者 LIPiston
REM 作用 Steam 账号切换器启动脚本，用于启动 PowerShell 版本的切换工具
REM 支持平台 Windows
REM
REM --- 说明 ---
REM 需要和 SteamSwitcher.ps1 放在同一目录下运行

@echo off
chcp 65001 >nul
setlocal EnableExtensions
title Steam Account Switcher
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SteamSwitcher.ps1"
echo 切换完成！
timeout /t 5