@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
echo SysAdminSuite - Cybernet COM Port AutoFix
echo Mode: APPLY + RESTART
echo Evidence: C:\Temp\CybernetCOM\autofix_*
echo Use only on the local Cybernet before final app binding.
echo.
powershell.exe -NoProfile -Command "if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if not "%ERRORLEVEL%"=="0" (
  echo Requesting Administrator permission for Cybernet COM Port AutoFix...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c ""%~f0"" %*' -Verb RunAs"
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-CybernetComPortAutoFix.ps1" -Apply -Restart %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Cybernet COM Port AutoFix failed. Check the console output and evidence folder.
endlocal & exit /b %EXITCODE%
