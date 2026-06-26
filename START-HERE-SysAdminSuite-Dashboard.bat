@echo off
setlocal enabledelayedexpansion
title SysAdminSuite Dashboard

echo.
echo ==========================================
echo   SysAdminSuite Dashboard
echo ==========================================
echo.
echo Double-click launcher - no commands to memorize.
echo This opens the local dashboard and tutorial.
echo The first run may take a minute while the dashboard app is prepared.
echo No internet is required to use the dashboard after that.
echo.

set "ROOT=%~dp0"
cd /d "%ROOT%"
set "HEALTH_URL=http://127.0.0.1:5000/dashboard/"

if exist "%ROOT%app\bin\SysAdminSuite.DashboardHost.exe" (
    echo Packaged field release detected - dashboard app is already included.
    echo No build step is required on this machine.
    echo.
) else (
    echo Source checkout detected - the dashboard app may be prepared on first run.
    echo If this machine has the .NET SDK, the launcher will build it automatically.
    echo If not, ask for the packaged SysAdminSuite Dashboard field release instead.
    echo.
)

if not exist "%ROOT%Launch-SysAdminSuiteDashboard.Host.bat" (
    echo Could not find Launch-SysAdminSuiteDashboard.Host.bat.
    echo Make sure you are running this from the SysAdminSuite repo root.
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

echo Starting the dashboard host^.^.^.
echo If this is the first run, the dashboard app will be prepared automatically now.
call "%ROOT%Launch-SysAdminSuiteDashboard.Host.bat" --no-browser
set "RC=%errorlevel%"

if "%RC%"=="2" (
    echo.
    echo Source checkout without the .NET SDK ^(dotnet^).
    echo.
    echo The dashboard app could not be built on this machine.
    echo.
    echo This usually means the .NET SDK is missing or blocked.
    echo.
    echo Ask for the packaged SysAdminSuite Dashboard field release ^(pre-built host under app\bin^),
    echo or have IT/admin prepare this workstation.
    echo.
    echo Do not use CLI survey commands unless the dashboard or runbook gives you one.
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

if not "%RC%"=="0" (
    echo.
    echo The dashboard app could not be built on this machine.
    echo.
    echo This usually means the .NET SDK is missing or blocked on a source checkout.
    echo.
    echo Ask for the packaged SysAdminSuite Dashboard field release ^(pre-built host under app\bin^),
    echo or have IT/admin prepare this workstation.
    echo.
    echo Do not use CLI survey commands unless the dashboard or runbook gives you one.
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

echo Waiting for the dashboard to be ready^.^.^.
set "HOST_UP=0"
for /L %%i in (1,1,20) do (
    if "!HOST_UP!"=="0" (
        curl.exe -s -o nul --max-time 2 "%HEALTH_URL%" >nul 2>nul && set "HOST_UP=1"
        if "!HOST_UP!"=="0" timeout /t 1 /nobreak >nul
    )
)

if not "!HOST_UP!"=="1" (
    echo.
    echo The dashboard host did not respond on http://127.0.0.1:5000 .
    echo.
    echo Ask for the packaged SysAdminSuite Dashboard release, or have IT/admin prepare this workstation.
    echo.
    echo Do not use CLI survey commands unless the dashboard or runbook gives you one.
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

echo Opening dashboard and Cybernet tutorial in your browser...
start "" "http://127.0.0.1:5000/dashboard/?tutorial=cybernet"

echo.
echo If the page did not open, paste this into your browser:
echo   http://127.0.0.1:5000/dashboard/?tutorial=cybernet
echo.
echo A tray icon should appear. Right-click it for Open Dashboard, Copy URL, or Stop.
echo.
echo Press any key to close this window. The dashboard keeps running in the tray.
pause >nul
exit /b 0
