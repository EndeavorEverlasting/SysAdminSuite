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
    echo [SAS][failed] Git Bash was not found. Install Git for Windows or use the packaged dashboard field release.
    exit /b 2
)

echo [SAS][running] Preparing dashboard dependencies and host for first use...
"%BASH_EXE%" -lc "cd '%ROOT:\=/%' && bash scripts/ensure-dashboard-host.sh"
set "ENSURE_RC=%errorlevel%"

if defined BASH_EXE (
    "%BASH_EXE%" -lc "cd '%ROOT:\=/%' && export SAS_UPDATE_STATE='%SAS_UPDATE_STATE%' SAS_UPDATE_MODE='%SAS_UPDATE_MODE%' && bash scripts/sas-write-toolbox-status.sh" 2>nul
)

if not "%ENSURE_RC%"=="0" (
    rem The .NET dashboard host could not be prepared on this machine. Bridge the
    rem gap with the local-only Python dashboard fallback so a double-click still
    rem serves the dashboard instead of dead-ending to manual CLI usage.
    call :start_fallback
    if defined FALLBACK_OK (
        echo [SAS][complete] Local Python dashboard fallback started.
        exit /b 0
    )
    if "%ENSURE_RC%"=="2" (
        echo [SAS][failed] Dashboard dependency preparation failed.
        exit /b 2
    )
    echo [SAS][failed] Dashboard host preparation needs IT or admin attention.
    exit /b 3
)

call :find_host
if not defined HOST_EXE (
    rem Host preparation reported success but no executable was located. Try the
    rem local-only Python dashboard fallback before failing.
    call :start_fallback
    if defined FALLBACK_OK (
        echo [SAS][complete] Local Python dashboard fallback started.
        exit /b 0
    )
    echo [SAS][failed] Host preparation completed but no dashboard executable was found.
    exit /b 3
)

:start_host
if exist "%ROOT%app\bin\SysAdminSuite.DashboardHost.exe" (
    if /i not "%HOST_EXE%"=="%ROOT%app\bin\SysAdminSuite.DashboardHost.exe" (
        rem other host path won; packaged layout not primary
    ) else (
        echo Using packaged dashboard host from app\bin.
    )
)
start "" /B "%HOST_EXE%" %*
echo [SAS][complete] Dashboard host process started.
exit /b 0

:find_host
set "HOST_EXE="
if exist "%ROOT%app\bin\SysAdminSuite.DashboardHost.exe" set "HOST_EXE=%ROOT%app\bin\SysAdminSuite.DashboardHost.exe"
if not defined HOST_EXE if exist "%ROOT%dist\SysAdminSuiteDashboard\SysAdminSuite Dashboard.exe" set "HOST_EXE=%ROOT%dist\SysAdminSuiteDashboard\SysAdminSuite Dashboard.exe"
if not defined HOST_EXE if exist "%ROOT%tools\publish\SysAdminSuite.DashboardHost\SysAdminSuite.DashboardHost.exe" set "HOST_EXE=%ROOT%tools\publish\SysAdminSuite.DashboardHost\SysAdminSuite.DashboardHost.exe"
if not defined HOST_EXE if exist "%ROOT%src\SysAdminSuite.DashboardHost\bin\Release\net8.0-windows\SysAdminSuite.DashboardHost.exe" set "HOST_EXE=%ROOT%src\SysAdminSuite.DashboardHost\bin\Release\net8.0-windows\SysAdminSuite.DashboardHost.exe"
rem Runtime-identifier (win-x64) builds land in a nested RID folder; include
rem those so an already-built host is not missed and the launcher needlessly
rem falls back.
if not defined HOST_EXE if exist "%ROOT%src\SysAdminSuite.DashboardHost\bin\Release\net8.0-windows\win-x64\SysAdminSuite.DashboardHost.exe" set "HOST_EXE=%ROOT%src\SysAdminSuite.DashboardHost\bin\Release\net8.0-windows\win-x64\SysAdminSuite.DashboardHost.exe"
if not defined HOST_EXE if exist "%ROOT%src\SysAdminSuite.DashboardHost\bin\Release\net8.0-windows\win-x64\publish\SysAdminSuite.DashboardHost.exe" set "HOST_EXE=%ROOT%src\SysAdminSuite.DashboardHost\bin\Release\net8.0-windows\win-x64\publish\SysAdminSuite.DashboardHost.exe"
if not defined HOST_EXE if exist "%ROOT%src\SysAdminSuite.DashboardHost\bin\Debug\net8.0-windows\SysAdminSuite.DashboardHost.exe" set "HOST_EXE=%ROOT%src\SysAdminSuite.DashboardHost\bin\Debug\net8.0-windows\SysAdminSuite.DashboardHost.exe"
if not defined HOST_EXE if exist "%ROOT%src\SysAdminSuite.DashboardHost\bin\Debug\net8.0-windows\win-x64\SysAdminSuite.DashboardHost.exe" set "HOST_EXE=%ROOT%src\SysAdminSuite.DashboardHost\bin\Debug\net8.0-windows\win-x64\SysAdminSuite.DashboardHost.exe"
exit /b 0

:start_fallback
rem Local-only Python dashboard fallback. Keeps the double-click front door
rem working when the .NET host is unavailable. server.py is the suite's own
rem server (not a raw python -m http.server) and binds 127.0.0.1 only.
set "FALLBACK_OK="
set "PY_OK="
where py >nul 2>nul && set "PY_OK=1"
if not defined PY_OK where python >nul 2>nul && set "PY_OK=1"
if not defined PY_OK where python3 >nul 2>nul && set "PY_OK=1"
if not defined PY_OK (
    echo [SAS][skipped] Python fallback unavailable because no Python runtime was found.
    goto :eof
)
if not exist "%ROOT%server.py" (
    echo [SAS][skipped] Python fallback unavailable because server.py was not found.
    goto :eof
)
echo [SAS][running] The .NET dashboard host is unavailable; starting the local Python dashboard fallback...
start "SysAdminSuite Dashboard (fallback)" /MIN "%BASH_EXE%" -lc "cd '%ROOT:\=/%' && SAS_DASHBOARD_BIND=127.0.0.1 SAS_DASHBOARD_PORT=5000 bash scripts/sas-serve-dashboard-fallback.sh"
set "FALLBACK_OK=1"
goto :eof

:find_bash
set "BASH_EXE="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if defined BASH_EXE exit /b 0
for /f "delims=" %%B in ('where bash 2^>nul') do (
    if not defined BASH_EXE set "BASH_EXE=%%B"
)
exit /b 0
