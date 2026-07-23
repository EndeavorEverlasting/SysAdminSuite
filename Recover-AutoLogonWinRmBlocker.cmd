@echo off
setlocal EnableExtensions

if not "%~1"=="" (
    echo This technician recovery launcher does not accept command-line arguments.
    echo Double-click it and choose the recovery action from the menu.
    exit /b 2
)

cd /d "%~dp0"
set "SCRIPT=%~dp0scripts\Start-SasAutoLogonWinRmRecovery.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: AutoLogon WinRM-blocker recovery script was not found:
    echo %SCRIPT%
    pause
    exit /b 2
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Action Menu
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo AutoLogon recovery stopped with exit code %EXITCODE%.
) else (
    echo AutoLogon recovery action completed.
)
echo Press any key to close this window.
pause >nul

exit /b %EXITCODE%
