@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "VENV_DIR=%~dp0venv"
set "PYTHON_EXE=%VENV_DIR%\Scripts\python.exe"
if not exist "%PYTHON_EXE%" py -3 -m venv "%VENV_DIR%"
"%PYTHON_EXE%" -m pip install --upgrade pip psutil
"%PYTHON_EXE%" -m unittest discover -s tests -v
pause
