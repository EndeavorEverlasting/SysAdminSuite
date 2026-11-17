@echo off
setlocal
set "SCRIPT=%~dp0scripts\Close-SasChromeGhostSession.ps1"

if not exist "%SCRIPT%" (
  echo ERROR: Missing Chrome ghost-session script: %SCRIPT%
  exit /b 2
)

set "MODE=%~1"
if /I "%MODE%"=="apply" goto :apply
if /I "%MODE%"=="close" goto :apply
if /I "%MODE%"=="-Apply" goto :apply
if not "%MODE%"=="" (
  echo Usage: Close-ChromeGhostSession.cmd [apply]
  echo Default is discover/dry-run. Pass apply to terminate classified ghost roots only.
  exit /b 2
)

where pwsh.exe >nul 2>&1
if errorlevel 1 goto :windowsps_discover
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b %ERRORLEVEL%

:windowsps_discover
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b %ERRORLEVEL%

:apply
where pwsh.exe >nul 2>&1
if errorlevel 1 goto :windowsps_apply
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Apply
exit /b %ERRORLEVEL%

:windowsps_apply
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Apply
exit /b %ERRORLEVEL%
