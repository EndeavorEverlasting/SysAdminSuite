@echo off
setlocal
cd /d "%~dp0"

where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    set "SAS_PS=pwsh"
) else (
    set "SAS_PS=powershell.exe"
)

echo [SAS][running] Harness validator child process started.
"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\validate-sysadmin-harness.ps1"
set "SAS_EXIT=%ERRORLEVEL%"
echo.
if "%SAS_EXIT%"=="0" (
    echo [SAS][complete] Harness validator finished successfully.
) else (
    echo [SAS][failed] Harness validator exited with code %SAS_EXIT%.
)
pause
exit /b %SAS_EXIT%
