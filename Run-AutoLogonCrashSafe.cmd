@echo off
setlocal EnableExtensions

if "%~1"=="" (
  echo Usage: Run-AutoLogonCrashSafe.cmd HOST_OR_FQDN
  echo.
  pause
  exit /b 2
)

rem %~dp0 always ends in a backslash. Normalize it through "." before the
rem powershell.exe -File boundary so the closing quote cannot absorb the
rem following -ConfirmDeployment switch on Windows command-line parsing.
set "SAS_ROOT=%~dp0."
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1" -ComputerName "%~1" -RepositoryRoot "%SAS_ROOT%" -ConfirmDeployment
set "SAS_EXIT=%ERRORLEVEL%"

echo.
echo Crash-safe diagnostics remain under:
echo   %%LOCALAPPDATA%%\SysAdminSuite\field-runs\autologon
echo.
pause

for %%# in (%SAS_EXIT%) do endlocal & exit /b %%#
