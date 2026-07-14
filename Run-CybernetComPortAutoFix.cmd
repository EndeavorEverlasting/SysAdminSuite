@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "SAS_COM_AUTOFIX_ARGS=%*"
echo SysAdminSuite - Cybernet COM Port AutoFix
echo Mode: APPLY + RESTART
echo Evidence: C:\Temp\CybernetCOM\autofix_*
echo Use only on the local Cybernet before final app binding.
echo.
if defined SAS_COM_AUTOFIX_ARGS (
  echo ERROR: The technician apply launcher does not accept arguments. Use the tracked PowerShell script directly only for an approved advanced override.
  exit /b 2
)
powershell.exe -NoProfile -File "%SCRIPT_DIR%scripts\Start-CybernetComPortAutoFix.ps1" -Mode Apply
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Cybernet COM Port AutoFix failed. Check the console output and evidence folder.
endlocal & exit /b %EXITCODE%
