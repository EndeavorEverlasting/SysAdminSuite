@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
  echo Requesting Administrator permission for Cybernet COM Port AutoFix...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c ""%~f0"" %*' -Verb RunAs"
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-CybernetComPortAutoFix.ps1" -Apply -Restart %*
endlocal
