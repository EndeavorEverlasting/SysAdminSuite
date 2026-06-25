@echo off
setlocal

rem Runtime launcher for packaged deployments (no git required).
set "ROOT=%~dp0"
set "APP_ROOT=%ROOT%app"

echo SysAdminSuite - Runtime Launcher
echo.
echo  [1] Launch GUI (PowerShell WinForms)
echo  [2] Launch Web Dashboard (PowerShell + Python)
echo  [3] Launch Web Dashboard (no PowerShell, tray host)
echo.
set /p CHOICE="Select an option (1, 2, or 3): "

if "%CHOICE%"=="1" goto :launch_gui
if "%CHOICE%"=="2" goto :launch_dashboard
if "%CHOICE%"=="3" goto :launch_dashboard_host

echo Invalid selection. Please enter 1, 2, or 3.
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

:launch_dashboard_host
rem PS-independent dashboard host (.NET 8 tray + Kestrel; see docs/GUI_HOST_MIGRATION.md)
if exist "%APP_ROOT%\bin\SysAdminSuite.DashboardHost.exe" (
    start "" /B "%APP_ROOT%\bin\SysAdminSuite.DashboardHost.exe"
    exit /b 0
)

if exist "%ROOT%tools\publish\SysAdminSuite.DashboardHost\SysAdminSuite.DashboardHost.exe" (
    start "" /B "%ROOT%tools\publish\SysAdminSuite.DashboardHost\SysAdminSuite.DashboardHost.exe"
    exit /b 0
)

if exist "%ROOT%Launch-SysAdminSuiteDashboard.Host.bat" (
    call "%ROOT%Launch-SysAdminSuiteDashboard.Host.bat"
    exit /b %ERRORLEVEL%
)

echo Unable to locate SysAdminSuite.DashboardHost.exe or Launch-SysAdminSuiteDashboard.Host.bat.
exit /b 1
