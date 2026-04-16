@echo off
setlocal

rem Runtime launcher for packaged deployments (no git required).
set "ROOT=%~dp0"
set "APP_ROOT=%ROOT%app"

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
