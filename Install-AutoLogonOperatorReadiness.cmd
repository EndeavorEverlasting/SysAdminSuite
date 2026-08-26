@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - Install AutoLogon Operator Readiness

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Install-SasAutoLogonOperatorReadiness.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if "%EXITCODE%"=="0" (
  echo AutoLogon operator-readiness surfaces installed.
  echo Open a NEW NON-ELEVATED true standard-user PowerShell window and run:
  echo powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ProgramData%\SysAdminSuite\bin\Test-SasAutoLogonOperatorReadiness.ps1" -RequireStandardUser
) else (
  echo Installation stopped with exit code %EXITCODE%.
)
echo.
pause
endlocal & exit /b %EXITCODE%
