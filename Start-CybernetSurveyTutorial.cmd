@echo off
setlocal

rem SysAdminSuite Cybernet Survey Tutorial Launcher
rem Double-click this file from the repository root after cloning.
rem It opens the local dashboard and auto-starts the Cybernet Survey tutorial.
rem This launcher does not run Naabu, Nmap, PowerShell survey commands, credentials, or target probes.

set "REPO_ROOT=%~dp0"
set "DASHBOARD_FILE=%REPO_ROOT%dashboard\index.html"

if not exist "%DASHBOARD_FILE%" (
  echo SysAdminSuite dashboard was not found:
  echo   %DASHBOARD_FILE%
  echo.
  echo Run this launcher from the cloned SysAdminSuite repository root.
  pause
  exit /b 1
)

set "DASHBOARD_URI="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=(Resolve-Path -LiteralPath '%DASHBOARD_FILE%').ProviderPath; ([Uri]$p).AbsoluteUri + '?tutorial=cybernet'" 2^>nul`) do set "DASHBOARD_URI=%%I"

if defined DASHBOARD_URI (
  start "" "%DASHBOARD_URI%"
) else (
  rem Fallback: opens the dashboard without the auto-start query flag.
  start "" "%DASHBOARD_FILE%"
)

endlocal
exit /b 0
