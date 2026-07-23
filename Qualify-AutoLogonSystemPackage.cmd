@echo off
setlocal EnableExtensions

if not "%~1"=="" (
    echo This qualification launcher does not accept command-line arguments.
    echo Double-click it and choose the bounded qualification action from the menu.
    exit /b 2
)

cd /d "%~dp0"
set "SCRIPT=%~dp0scripts\Invoke-SasAutoLogonSystemQualification.ps1"

if not exist "%SCRIPT%" (
    echo ERROR: AutoLogon SYSTEM qualification script was not found:
    echo %SCRIPT%
    pause
    exit /b 2
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Action Menu
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo AutoLogon SYSTEM qualification stopped with exit code %EXITCODE%.
) else (
    echo AutoLogon SYSTEM qualification action completed.
)
echo Press any key to close this window.
pause >nul

exit /b %EXITCODE%
