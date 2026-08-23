@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

set "STEAM_PATH=%~1"
if not defined STEAM_PATH call :detect_steam_path
if not defined STEAM_PATH (
    echo 未找到 Steam 安装目录。
    exit /b 1
)

set "PROJECT_ROOT=%~dp0"
if "%PROJECT_ROOT:~-1%"=="\" set "PROJECT_ROOT=%PROJECT_ROOT:~0,-1%"
set "BACKUP_ROOT=%PROJECT_ROOT%\backups"
set "APP_ID=730"
set "CFG_REL=730\local\cfg"

if /i "%~2"=="backup" call :cli_backup & exit /b !errorlevel!
if /i "%~2"=="restore" call :cli_restore "%~3" & exit /b !errorlevel!

goto :menu

:detect_steam_path
set "STEAM_PATH="
for %%K in ("HKCU\Software\Valve\Steam" "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" "HKLM\SOFTWARE\Valve\Steam") do (
    if not defined STEAM_PATH (
        for /f "tokens=2,*" %%A in ('reg query %%~K /v SteamPath 2^>nul ^| findstr /i "SteamPath"') do if exist "%%B\" set "STEAM_PATH=%%B"
    )
    if not defined STEAM_PATH (
        for /f "tokens=2,*" %%A in ('reg query %%~K /v InstallPath 2^>nul ^| findstr /i "InstallPath"') do if exist "%%B\" set "STEAM_PATH=%%B"
    )
)
if not defined STEAM_PATH if exist "C:\Program Files (x86)\Steam\" set "STEAM_PATH=C:\Program Files (x86)\Steam"
exit /b

:title
cls
echo ========================================
echo         CS2 CFG Switcher
echo ========================================
echo.
exit /b

:pause_return
echo.
set "_pause="
set /p "_pause=按 Enter 返回菜单"
exit /b

:sanitize
set "SAN=%~1"
if not defined SAN set "SAN=unknown"
set "SAN=%SAN:\=_%"
set "SAN=%SAN:/=_%"
set "SAN=%SAN::=_%"
set "SAN=%SAN:*=_%"
set "SAN=%SAN:?=_%"
set "SAN=%SAN:<=_%"
set "SAN=%SAN:>=_%"
set "SAN=%SAN:|=_%"
set "SAN=%SAN: =_%"
exit /b

:timestamp
set "STAMP=%date%_%time%"
set "STAMP=%STAMP:/=-%"
set "STAMP=%STAMP:\=-%"
set "STAMP=%STAMP::=-%"
set "STAMP=%STAMP:.=-%"
set "STAMP=%STAMP: =0%"
set "STAMP=%STAMP:,=-%"
exit /b

:read_loginusers
set "RECENT_ID="
set "CURRENT_ID="
set "LOGIN_FILE=%STEAM_PATH%\config\loginusers.vdf"
if not exist "%LOGIN_FILE%" exit /b

for /f "usebackq tokens=* delims=" %%L in ("%LOGIN_FILE%") do (
    set "LINE=%%L"
    set "LINE=!LINE:"= !"
    for /f "tokens=1,*" %%A in ("!LINE!") do (
        set "K=%%A"
        set "V=%%B"
        for /f "tokens=* delims= " %%T in ("!V!") do set "V=%%T"
        echo(!K!| findstr /r "^[0-9][0-9]*$" >nul
        if not errorlevel 1 (
            set "CURRENT_ID="
            for /f %%S in ('powershell.exe -NoProfile -Command "[int64]'!K!' - 76561197960265728" 2^>nul') do set "CURRENT_ID=%%S"
        )
        if /i "!K!"=="AccountName" if defined CURRENT_ID (
            set "ACCOUNT_!CURRENT_ID!=!V!"
        )
        if /i "!K!"=="PersonaName" if defined CURRENT_ID (
            set "PERSONA_!CURRENT_ID!=!V!"
        )
        if /i "!K!"=="MostRecent" if defined CURRENT_ID if "!V:~0,1!"=="1" set "RECENT_ID=!CURRENT_ID!"
    )
)
exit /b

:load_users
call :read_loginusers
set /a USER_COUNT=0
for /d %%D in ("%STEAM_PATH%\userdata\*") do (
    if exist "%%~fD\%CFG_REL%\" (
        set /a USER_COUNT+=1
        set "USER_!USER_COUNT!=%%~nxD"
        set "USER_CFG_!USER_COUNT!=%%~fD\%CFG_REL%"
        set "P=!PERSONA_%%~nxD!"
        set "A=!ACCOUNT_%%~nxD!"
        if defined A if defined P set "P=!A! / !P!"
        if defined A if not defined P set "P=!A!"
        if not defined P set "P=unknown"
        set "USER_NAME_!USER_COUNT!=!P!"
        if "%%~nxD"=="%RECENT_ID%" set "RECENT_INDEX=!USER_COUNT!"
    )
)
exit /b

:select_user
call :load_users
if "%USER_COUNT%"=="0" (
    echo 错误：没有找到任何包含 CS2 cfg 的 Steam 用户目录。
    echo 请确认 CS2 已运行过，目标目录应类似：Steam\userdata\SteamID\730\local\cfg
    exit /b 1
)

if defined RECENT_INDEX if not "%FORCE_USER_PICK%"=="1" (
    set "SELECTED_ID=!USER_%RECENT_INDEX%!"
    set "SELECTED_NAME=!USER_NAME_%RECENT_INDEX%!"
    set "SELECTED_CFG=!USER_CFG_%RECENT_INDEX%!"
    exit /b 0
)

if "%USER_COUNT%"=="1" (
    set "SELECTED_ID=!USER_1!"
    set "SELECTED_NAME=!USER_NAME_1!"
    set "SELECTED_CFG=!USER_CFG_1!"
    exit /b 0
)

echo 检测到多个 Steam 用户，请选择当前要操作的用户：
for /l %%I in (1,1,%USER_COUNT%) do echo %%I. !USER_%%I! (!USER_NAME_%%I!)

:select_user_loop
set "CHOICE="
set "CHOICE_NUM="
set /p "CHOICE=输入序号: "
if not defined CHOICE exit /b 1
set /a CHOICE_NUM=!CHOICE! 2>nul
if not defined CHOICE_NUM goto bad_user_choice
if !CHOICE_NUM! LSS 1 goto bad_user_choice
if !CHOICE_NUM! GTR %USER_COUNT% goto bad_user_choice
call set "SELECTED_ID=%%USER_%CHOICE_NUM%%%"
call set "SELECTED_NAME=%%USER_NAME_%CHOICE_NUM%%%"
call set "SELECTED_CFG=%%USER_CFG_%CHOICE_NUM%%%"
goto select_user_done

:select_user_done
if defined SELECTED_ID exit /b 0
exit /b 1

:bad_user_choice
echo 无效选择。
goto :select_user_loop

:new_backup
set "BACKUP_PREFIX=%~1"
if not exist "%BACKUP_ROOT%" mkdir "%BACKUP_ROOT%" >nul 2>nul
call :timestamp
set "BACKUP_NAME=%BACKUP_PREFIX%%STAMP%_%SELECTED_ID%"
set "BACKUP_PATH=%BACKUP_ROOT%\%BACKUP_NAME%"
set "BACKUP_CFG=%BACKUP_PATH%\cfg"
mkdir "%BACKUP_PATH%" >nul 2>nul
robocopy "%SELECTED_CFG%" "%BACKUP_CFG%" /E /NFL /NDL /NJH /NJS /NC /NS /NP >nul
if %errorlevel% GEQ 8 exit /b %errorlevel%
(
    echo {
    echo   "createdAt": "%date% %time%",
    echo   "steamId": "%SELECTED_ID%",
    echo   "personaName": "%SELECTED_NAME%",
    echo   "sourceCfgPath": "%SELECTED_CFG:\=\\%",
    echo   "backupCfgPath": "%BACKUP_CFG:\=\\%",
    echo   "tool": "cs2-cfg-switcher.bat"
    echo }
) > "%BACKUP_PATH%\manifest.json"
exit /b 0

:backup_current
call :title
set "FORCE_USER_PICK=1"
call :select_user
if errorlevel 1 (
    set "FORCE_USER_PICK="
    call :pause_return
    exit /b
)
set "FORCE_USER_PICK="
echo 当前目标：%SELECTED_CFG%
call :new_backup ""
if errorlevel 1 (
    echo 备份失败。
) else (
    echo 备份完成：%BACKUP_PATH%
)
call :pause_return
exit /b

:cli_backup
call :select_user || exit /b 1
call :new_backup ""
if errorlevel 1 exit /b %errorlevel%
echo 备份完成：%BACKUP_PATH%
exit /b 0

:cli_restore
set "RESTORE_INDEX=%~1"
if not defined RESTORE_INDEX set "RESTORE_INDEX=1"
call :select_user || exit /b 1
call :load_backups
if "%BACKUP_COUNT%"=="0" (
    echo 还没有可恢复的备份。请先执行 backup。
    exit /b 1
)
set /a CHOICE_NUM=%RESTORE_INDEX% 2>nul
if "%CHOICE_NUM%"=="" exit /b 1
if %CHOICE_NUM% LSS 1 exit /b 1
if %CHOICE_NUM% GTR %BACKUP_COUNT% exit /b 1
set "RESTORE_CFG=!BACKUP_CFG_%CHOICE_NUM%!"
call :new_backup "pre-restore-"
if errorlevel 1 exit /b %errorlevel%
if exist "%SELECTED_CFG%\" rmdir /s /q "%SELECTED_CFG%"
robocopy "%RESTORE_CFG%" "%SELECTED_CFG%" /E /NFL /NDL /NJH /NJS /NC /NS /NP >nul
if %errorlevel% GEQ 8 exit /b %errorlevel%
echo 恢复完成。
exit /b 0

:load_backups
set /a BACKUP_COUNT=0
if not exist "%BACKUP_ROOT%\" exit /b
for /d %%B in ("%BACKUP_ROOT%\*") do (
    set "BNAME=%%~nxB"
    if /i not "!BNAME:~0,12!"=="pre-restore-" if exist "%%~fB\cfg\" (
        set /a BACKUP_COUNT+=1
        set "BACKUP_!BACKUP_COUNT!=%%~nxB"
        set "BACKUP_PATH_!BACKUP_COUNT!=%%~fB"
        set "BACKUP_CFG_!BACKUP_COUNT!=%%~fB\cfg"
    )
)
exit /b

:restore_backup
call :title
call :select_user
if errorlevel 1 (
    call :pause_return
    exit /b
)
call :load_backups
if "%BACKUP_COUNT%"=="0" (
    echo 还没有可恢复的备份。请先执行选项 1。
    call :pause_return
    exit /b
)

echo 当前目标：%SELECTED_CFG%
echo 请选择要恢复的备份：
for /l %%I in (1,1,%BACKUP_COUNT%) do echo %%I. !BACKUP_%%I!

:select_backup_loop
set "CHOICE="
set "CHOICE_NUM="
set /p "CHOICE=输入序号，或输入 q 取消: "
if not defined CHOICE exit /b
if /i "!CHOICE!"=="q" exit /b
set /a CHOICE_NUM=!CHOICE! 2>nul
if not defined CHOICE_NUM goto bad_backup_choice
if !CHOICE_NUM! LSS 1 goto bad_backup_choice
if !CHOICE_NUM! GTR %BACKUP_COUNT% goto bad_backup_choice
call set "RESTORE_NAME=%%BACKUP_%CHOICE_NUM%%%"
call set "RESTORE_CFG=%%BACKUP_CFG_%CHOICE_NUM%%%"
goto restore_confirm

:bad_backup_choice
echo 无效选择。
goto :select_backup_loop

:restore_confirm
echo.
echo 将使用以下备份覆盖目标用户的 cfg：
echo 备份：%RESTORE_CFG%
echo 目标：%SELECTED_CFG%

echo 恢复前自动备份当前 cfg...
call :new_backup "pre-restore-"
if errorlevel 1 (
    echo 恢复前备份失败，已停止。
    call :pause_return
    exit /b
)
echo 恢复前备份完成：%BACKUP_PATH%

if exist "%SELECTED_CFG%\" rmdir /s /q "%SELECTED_CFG%"
robocopy "%RESTORE_CFG%" "%SELECTED_CFG%" /E /NFL /NDL /NJH /NJS /NC /NS /NP >nul
if %errorlevel% GEQ 8 (
    echo 恢复失败。
) else (
    echo 恢复完成。
)
call :pause_return
exit /b

:menu
call :title
echo Steam 路径：%STEAM_PATH%
echo 备份目录：%BACKUP_ROOT%
echo.
echo 1. 从已登录 Steam 用户中选择一个备份 CS2 cfg
echo 2. 选择目标 Steam 用户，再选择备份覆盖到该用户
echo 3. 退出
echo.
set "MENU_CHOICE="
set /p "MENU_CHOICE=请选择: "
if not defined MENU_CHOICE exit /b 0
if "%MENU_CHOICE%"=="1" call :backup_current
if "%MENU_CHOICE%"=="2" call :restore_backup
if "%MENU_CHOICE%"=="3" exit /b 0
if not "%MENU_CHOICE%"=="1" if not "%MENU_CHOICE%"=="2" if not "%MENU_CHOICE%"=="3" (
    echo 无效选择。
    timeout /t 1 >nul
)
goto :menu
