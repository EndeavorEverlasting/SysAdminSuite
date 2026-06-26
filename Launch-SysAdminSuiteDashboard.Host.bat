@echo off
:: Launch-SysAdminSuiteDashboard.Host.bat
:: Field-safe dashboard host launcher.
::
:: Discovers the SysAdminSuite dashboard host executable. On first run, if the
:: host is missing, this AUTOMATICALLY builds it via
:: tools\publish-dashboard-entrypoint.ps1 so the field user never has to run a
:: publish command by hand. It then starts the tray host which serves
:: http://127.0.0.1:5000 (Open Dashboard, Copy URL, Stop).
::
:: Exit codes (consumed by START-HERE-SysAdminSuite-Dashboard.bat):
::   0  host found or built, and started
::   2  .NET SDK (dotnet) missing - cannot build on this machine
::   3  auto-publish ran but the host could not be built or located

setlocal enabledelayedexpansion
set "ROOT=%~dp0"
set "UPDATE_HELPER=%ROOT%tools\update\Invoke-SysAdminSuiteUpdate.ps1"
set "FRESHNESS_JSON=%ROOT%dashboard\repo-freshness.json"

if exist "%UPDATE_HELPER%" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UPDATE_HELPER%" -CheckOnly -Quiet -StateJsonPath "%FRESHNESS_JSON%" >nul 2>nul
)

call :find_host
if defined HOST_EXE goto :start_host

:: Host missing on a source checkout: prepare automatically. Packaged field
:: releases ship app\bin\SysAdminSuite.DashboardHost.exe and skip this path.
echo Source checkout: preparing the dashboard app for first use. This can take a minute...
where dotnet >nul 2>nul
if errorlevel 1 exit /b 2

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\publish-dashboard-entrypoint.ps1"
if errorlevel 1 exit /b 3

call :find_host
if not defined HOST_EXE exit /b 3

:start_host
if exist "%ROOT%app\bin\SysAdminSuite.DashboardHost.exe" (
    if /i not "%HOST_EXE%"=="%ROOT%app\bin\SysAdminSuite.DashboardHost.exe" (
        rem other host path won; packaged layout not primary
    ) else (
        echo Using packaged dashboard host from app\bin.
    )
)
start "" /B "%HOST_EXE%" %*
exit /b 0

:find_host
set "HOST_EXE="
if exist "%ROOT%app\bin\SysAdminSuite.DashboardHost.exe" set "HOST_EXE=%ROOT%app\bin\SysAdminSuite.DashboardHost.exe"
if not defined HOST_EXE if exist "%ROOT%dist\SysAdminSuiteDashboard\SysAdminSuite Dashboard.exe" set "HOST_EXE=%ROOT%dist\SysAdminSuiteDashboard\SysAdminSuite Dashboard.exe"
if not defined HOST_EXE if exist "%ROOT%tools\publish\SysAdminSuite.DashboardHost\SysAdminSuite.DashboardHost.exe" set "HOST_EXE=%ROOT%tools\publish\SysAdminSuite.DashboardHost\SysAdminSuite.DashboardHost.exe"
if not defined HOST_EXE if exist "%ROOT%src\SysAdminSuite.DashboardHost\bin\Release\net8.0-windows\SysAdminSuite.DashboardHost.exe" set "HOST_EXE=%ROOT%src\SysAdminSuite.DashboardHost\bin\Release\net8.0-windows\SysAdminSuite.DashboardHost.exe"
if not defined HOST_EXE if exist "%ROOT%src\SysAdminSuite.DashboardHost\bin\Debug\net8.0-windows\SysAdminSuite.DashboardHost.exe" set "HOST_EXE=%ROOT%src\SysAdminSuite.DashboardHost\bin\Debug\net8.0-windows\SysAdminSuite.DashboardHost.exe"
exit /b 0
