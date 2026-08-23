@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem VMware Workstation Chinese localization installer.
rem Source: https://github.com/Kuroba-Sayuki/VMware-Workstation-Chinese-Localization
rem The repository states that its files are for learning/archival use only.

set "VMWARE_DIR=%ProgramFiles%\VMware\VMware Workstation"
set "MSG_DIR=%VMWARE_DIR%\messages\zh_CN"
set "PREF=%APPDATA%\VMware\preferences.ini"
set "DOWNLOAD_DIR=%TEMP%\VMware-Workstation-Chinese-Localization\VMware Workstation Messages\zh_CN"
set "BASE_URL=https://raw.githubusercontent.com/Kuroba-Sayuki/VMware-Workstation-Chinese-Localization/main/VMware%%20Workstation%%20Messages/zh_CN"

rem Relaunch with administrator rights because VMware is under Program Files.
net session >nul 2>&1
if not %ERRORLEVEL%==0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

if not exist "%VMWARE_DIR%\vmware.exe" (
    echo VMware Workstation was not found:
    echo   %VMWARE_DIR%
    exit /b 1
)

for %%F in (vmappsdk-zh_CN.dll vmui-zh_CN.dll vmware.vmsg) do (
    if not exist "%DOWNLOAD_DIR%\%%F" (
        echo Downloading %%F...
        if not exist "%DOWNLOAD_DIR%" mkdir "%DOWNLOAD_DIR%"
        powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='%BASE_URL%/%%F'; Invoke-WebRequest -Uri $u -OutFile '%DOWNLOAD_DIR%\%%F'"
        if errorlevel 1 (
            echo Failed to download %%F.
            exit /b 2
        )
    )
)

if exist "%MSG_DIR%" (
    echo The destination already exists; no files were overwritten:
    echo   %MSG_DIR%
    echo Remove it manually only after confirming it is safe to do so.
    exit /b 3
)

mkdir "%MSG_DIR%" || exit /b 4
for %%F in (vmappsdk-zh_CN.dll vmui-zh_CN.dll vmware.vmsg) do (
    copy /Y "%DOWNLOAD_DIR%\%%F" "%MSG_DIR%\" >nul || exit /b 5
)

if not exist "%APPDATA%\VMware" mkdir "%APPDATA%\VMware"
if exist "%PREF%" copy /Y "%PREF%" "%PREF%.bak-before-zh_CN" >nul

findstr /B /R /C:"pref\.locale[ ]*=" "%PREF%" >nul 2>&1
if errorlevel 1 (
    >>"%PREF%" echo pref.locale = "zh_CN"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%PREF%'; $s=Get-Content -Raw -LiteralPath $p; $s=[regex]::Replace($s,'(?m)^pref\.locale\s*=.*$','pref.locale = \"zh_CN\"'); Set-Content -LiteralPath $p -Value $s -Encoding UTF8"
)

echo.
echo Chinese localization installed successfully.
echo Files: %MSG_DIR%
echo Config: pref.locale = "zh_CN"
echo Backup: %PREF%.bak-before-zh_CN
echo Restart VMware Workstation to apply the language.
pause
endlocal
