@echo off
chcp 65001 >nul
title OBS 屏幕控制脚本

:: 检查管理员权限
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ============================================
    echo   错误：请右键此脚本，选择"以管理员身份运行"！
    echo ============================================
    pause
    exit /b
)

:menu
cls
echo ============================================
echo        OBS 屏幕保持唤醒 控制脚本
echo ============================================
echo.
echo   当前状态：
powercfg /requestsoverride | findstr /i "obs64.exe" >nul 2>&1
if %errorlevel% equ 0 (
    echo   [已启用] Windows 会忽略 OBS 的保持屏幕唤醒请求
) else (
    echo   [未启用] Windows 按默认规则处理 OBS 的唤醒请求
)
echo.
echo   1. 启用覆盖（允许自动熄屏）
echo   2. 关闭覆盖（恢复默认行为）
echo   3. 退出
echo.
echo ============================================
set /p choice=请输入选项 (1/2/3)：

if "%choice%"=="1" goto enable
if "%choice%"=="2" goto disable
if "%choice%"=="3" exit /b
echo.
echo   输入无效，请重新选择！
timeout /t 2 >nul
goto menu

:enable
cls
powercfg /requestsoverride PROCESS obs64.exe DISPLAY
echo.
echo ============================================
echo   已成功启用！
echo   Windows 现在会忽略 OBS 的屏幕唤醒请求。
echo   电脑可以在你设定的时间后自动熄屏。
echo ============================================
pause
goto menu

:disable
cls
powercfg /requestsoverride PROCESS obs64.exe
echo.
echo ============================================
echo   已成功关闭！
echo   Windows 已恢复对 OBS 的默认电源管理行为。
echo ============================================
pause
goto menu
