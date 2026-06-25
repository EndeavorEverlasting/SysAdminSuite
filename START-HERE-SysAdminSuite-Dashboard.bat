@echo off
setlocal
title SysAdminSuite Dashboard

echo.
echo ==========================================
echo   SysAdminSuite Dashboard
echo ==========================================
echo.
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
    echo Try this once from a developer machine with .NET 8 SDK installed:
    echo   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\publish-dashboard-entrypoint.ps1
    echo.
    echo Or build manually:
    echo   dotnet publish src\SysAdminSuite.DashboardHost -c Release -r win-x64 --self-contained false -o tools\publish\SysAdminSuite.DashboardHost
    echo.
    echo Then double-click this file again.
    echo.
    echo Advanced launchers are still available:
    echo   Launch-SysAdminSuiteDashboard.Host.bat
    echo   Launch-SysAdminSuite-Runtime.bat
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
