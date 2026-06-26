@echo off
:: Launch-SysAdminSuiteDashboard.Host.bat
:: Field-safe dashboard host launcher.
::
:: Discovers the SysAdminSuite dashboard host executable. On first run this
:: calls the Bash bootstrap, which can install the official Microsoft .NET 8
:: dependencies system-wide and build the host when it is missing. It then
:: starts the tray host which serves http://127.0.0.1:5000 (Open Dashboard,
:: Copy URL, Stop).
::
:: Exit codes (consumed by START-HERE-SysAdminSuite-Dashboard.bat):
::   0  host found or built, and started
::   2  Git Bash, curl, download, or checksum verification failed
::   3  Microsoft .NET install/build failed or needs IT/admin attention

setlocal enabledelayedexpansion
set "ROOT=%~dp0"

call :find_bash
if not defined BASH_EXE (
    echo Git Bash was not found. Install Git for Windows or use the packaged dashboard field release.
    exit /b 2
)

echo Preparing dashboard dependencies and host for first use...
"%BASH_EXE%" -lc "cd '%ROOT:\=/%' && bash scripts/ensure-dashboard-host.sh"
set "ENSURE_RC=%errorlevel%"
if "%ENSURE_RC%"=="2" exit /b 2
if not "%ENSURE_RC%"=="0" exit /b 3

if defined BASH_EXE (
    "%BASH_EXE%" -lc "cd '%ROOT:\=/%' && export SAS_UPDATE_STATE='%SAS_UPDATE_STATE%' SAS_UPDATE_MODE='%SAS_UPDATE_MODE%' && bash scripts/sas-write-toolbox-status.sh" 2>nul
)

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

:find_bash
set "BASH_EXE="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if defined BASH_EXE exit /b 0
for /f "delims=" %%B in ('where bash 2^>nul') do (
    if not defined BASH_EXE set "BASH_EXE=%%B"
)
exit /b 0
