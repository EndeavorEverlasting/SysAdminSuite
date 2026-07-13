@echo off
setlocal
cd /d "%~dp0"

where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    set "SAS_PS=pwsh"
) else (
    set "SAS_PS=powershell.exe"
)

echo [SAS] Running harness validation through PowerShell...
"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\validate-sysadmin-harness.ps1"
set "SAS_EXIT=%ERRORLEVEL%"
echo.
echo [SAS] Exit code: %SAS_EXIT%
pause
exit /b %SAS_EXIT%
