@echo off
setlocal EnableExtensions

if not "%~1"=="" (
    echo This technician launcher does not accept command-line arguments.
    echo Double-click it and choose the workflow action from the menu.
    exit /b 2
)

set "SCRIPT=%~dp0scripts\Start-SasAutoLogonStateDelta.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: AutoLogon verification launcher script was not found:
    echo %SCRIPT%
    pause
    exit /b 2
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Action Menu
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
    echo.
    echo AutoLogon verification stopped with exit code %EXITCODE%.
    pause
)

exit /b %EXITCODE%
