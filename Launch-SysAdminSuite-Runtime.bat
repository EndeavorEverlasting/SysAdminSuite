@echo off
setlocal

rem Runtime launcher for packaged deployments (no git required).
set "ROOT=%~dp0"
set "APP_ROOT=%ROOT%app"

echo SysAdminSuite - Runtime Launcher
echo.
echo  [1] Launch GUI
echo  [2] Launch Web Dashboard
echo.
set /p CHOICE="Select an option (1 or 2): "

if "%CHOICE%"=="1" goto :launch_gui
if "%CHOICE%"=="2" goto :launch_dashboard

echo Invalid selection. Please enter 1 or 2.
exit /b 1

:launch_gui
if exist "%APP_ROOT%\GUI\Start-SysAdminSuiteGui.ps1" (
    start "" /B powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%APP_ROOT%\GUI\Start-SysAdminSuiteGui.ps1"
    exit /b 0
)

if exist "%ROOT%GUI\Start-SysAdminSuiteGui.ps1" (
    start "" /B powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%ROOT%GUI\Start-SysAdminSuiteGui.ps1"
    exit /b 0
)

echo Unable to locate Start-SysAdminSuiteGui.ps1 in app\GUI or GUI.
exit /b 1

:launch_dashboard
if exist "%APP_ROOT%\Launch-SysAdminSuiteDashboard.ps1" (
    start "" /B powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%APP_ROOT%\Launch-SysAdminSuiteDashboard.ps1"
    exit /b 0
)

if exist "%ROOT%Launch-SysAdminSuiteDashboard.ps1" (
    start "" /B powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%ROOT%Launch-SysAdminSuiteDashboard.ps1"
    exit /b 0
)

echo Unable to locate Launch-SysAdminSuiteDashboard.ps1 in app\ or repo root.
exit /b 1
