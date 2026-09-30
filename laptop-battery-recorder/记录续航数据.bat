@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "VENV_DIR=%~dp0venv"
set "PYTHON_EXE=%VENV_DIR%\Scripts\python.exe"

where py >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python launcher py was not found. Install Python 3.11 or newer.
    pause
    exit /b 1
)

if not exist "%PYTHON_EXE%" (
    echo [INFO] Creating venv: %VENV_DIR%
    py -3 -m venv "%VENV_DIR%"
    if errorlevel 1 (
        echo [ERROR] Failed to create venv.
        pause
        exit /b 1
    )
)

echo [INFO] Installing/updating dependency psutil...
"%PYTHON_EXE%" -m pip install --upgrade pip psutil
if errorlevel 1 (
    echo [ERROR] Dependency installation failed.
    pause
    exit /b 1
)

echo [INFO] Starting battery recorder...
echo [INFO] Press Ctrl+C to stop and generate the summary.
"%PYTHON_EXE%" "%~dp0record_battery_session.py" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" echo [ERROR] Recorder exited with code: %EXIT_CODE%
pause
exit /b %EXIT_CODE%
