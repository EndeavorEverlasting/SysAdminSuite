@echo off
setlocal
title SysAdminSuite Dashboard

echo.
echo ==========================================
echo   SysAdminSuite Dashboard
echo ==========================================
echo.
echo Double-click launcher - no commands to memorize.
echo This opens the local dashboard and tutorial.
echo No internet is required after the repo is downloaded.
echo.
echo Starting the local dashboard at http://127.0.0.1:5000/dashboard/
echo.

set "ROOT=%~dp0"
cd /d "%ROOT%"

if not exist "%ROOT%Launch-SysAdminSuiteDashboard.Host.bat" (
    echo Could not find Launch-SysAdminSuiteDashboard.Host.bat.
    echo Make sure you are running this from the SysAdminSuite repo root.
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

echo Starting dashboard host...
call "%ROOT%Launch-SysAdminSuiteDashboard.Host.bat" --no-browser
if errorlevel 1 (
    echo.
    echo The dashboard host could not start.
    echo.
    echo A developer can build the host once on this machine:
    echo   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\publish-dashboard-entrypoint.ps1
    echo.
    echo That creates a local SysAdminSuite Dashboard.exe under dist\SysAdminSuiteDashboard\
    echo ^(not committed to git - built on your machine only^).
    echo.
    echo Then double-click this file again.
    echo.
    echo Shortcut tip: right-click this .bat file ^> Send to ^> Desktop ^(create shortcut^).
    echo.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

echo Waiting for the dashboard host to start...
timeout /t 3 /nobreak >nul

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
