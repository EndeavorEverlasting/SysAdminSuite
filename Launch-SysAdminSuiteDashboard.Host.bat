@echo off
:: Launch-SysAdminSuiteDashboard.Host.bat
:: PS-independent launcher for the SysAdminSuite web dashboard.
:: Spawns SysAdminSuite.DashboardHost.exe which serves dashboard/ over
:: http://127.0.0.1:5000 and shows a tray icon (Open, Copy URL, Stop).
:: No powershell.exe and no Python required.

setlocal
set "ROOT=%~dp0"

:: 1) Portable layout (zip): app\bin\SysAdminSuite.DashboardHost.exe
if exist "%ROOT%app\bin\SysAdminSuite.DashboardHost.exe" (
    start "" /B "%ROOT%app\bin\SysAdminSuite.DashboardHost.exe" %*
    exit /b 0
)

:: 2) Friendly field publish output (tools\publish-dashboard-entrypoint.ps1)
if exist "%ROOT%dist\SysAdminSuiteDashboard\SysAdminSuite Dashboard.exe" (
    start "" /B "%ROOT%dist\SysAdminSuiteDashboard\SysAdminSuite Dashboard.exe" %*
    exit /b 0
)

:: 3) Documented publish output (run dotnet publish to populate)
if exist "%ROOT%tools\publish\SysAdminSuite.DashboardHost\SysAdminSuite.DashboardHost.exe" (
    start "" /B "%ROOT%tools\publish\SysAdminSuite.DashboardHost\SysAdminSuite.DashboardHost.exe" %*
    exit /b 0
)

:: 4) Dev tree fallback (Release build)
if exist "%ROOT%src\SysAdminSuite.DashboardHost\bin\Release\net8.0-windows\SysAdminSuite.DashboardHost.exe" (
    start "" /B "%ROOT%src\SysAdminSuite.DashboardHost\bin\Release\net8.0-windows\SysAdminSuite.DashboardHost.exe" %*
    exit /b 0
)

:: 5) Dev tree fallback (Debug build)
if exist "%ROOT%src\SysAdminSuite.DashboardHost\bin\Debug\net8.0-windows\SysAdminSuite.DashboardHost.exe" (
    start "" /B "%ROOT%src\SysAdminSuite.DashboardHost\bin\Debug\net8.0-windows\SysAdminSuite.DashboardHost.exe" %*
    exit /b 0
)

echo Unable to locate SysAdminSuite.DashboardHost.exe.
echo Build with:
echo     powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\publish-dashboard-entrypoint.ps1
echo Or:
echo     dotnet publish src\SysAdminSuite.DashboardHost -c Release -r win-x64 --self-contained false -o tools\publish\SysAdminSuite.DashboardHost
exit /b 1
