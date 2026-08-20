@echo off
setlocal
set "SCRIPT=%~dp0scripts\Reset-SasClipboard.ps1"

if not exist "%SCRIPT%" (
  echo ERROR: Missing clipboard reset script: %SCRIPT%
  exit /b 2
)

where pwsh.exe >nul 2>&1
if errorlevel 1 goto :windowsps

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b %ERRORLEVEL%

:windowsps
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b %ERRORLEVEL%
