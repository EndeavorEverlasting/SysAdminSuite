@echo off
setlocal EnableExtensions DisableDelayedExpansion

if "%~1"=="" (
  echo Usage: Run-AutoLogon-ContiguousProgress.cmd HOST [--no-pause]
  echo.
  pause
  exit /b 2
)

set "SAS_PAUSE=1"
if not "%~2"=="" (
  if /I "%~2"=="--no-pause" (
    set "SAS_PAUSE=0"
  ) else (
    echo ERROR: The only optional argument is --no-pause.
    exit /b 2
  )
)
if not "%~3"=="" (
  echo ERROR: Too many arguments.
  exit /b 2
)

set "SAS_TARGET=%~1"
set "SAS_ROOT=%~dp0"
if "%SAS_ROOT:~-1%"=="\" set "SAS_ROOT=%SAS_ROOT:~0,-1%"
set "SAS_SCRIPT=%SAS_ROOT%\scripts\Invoke-SasAutoLogonWithContiguousProgress.ps1"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%SAS_SCRIPT%" (
  echo ERROR: contiguous AutoLogon progress wrapper is missing:
  echo   %SAS_SCRIPT%
  exit /b 3
)
if not exist "%SAS_PS%" (
  echo ERROR: Windows PowerShell 5.1 was not found:
  echo   %SAS_PS%
  exit /b 4
)

"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_SCRIPT%" -ComputerName "%SAS_TARGET%"
set "SAS_RC=%ERRORLEVEL%"

echo.
echo AutoLogon command exit code: %SAS_RC%
if "%SAS_PAUSE%"=="1" (
  echo Review the final classification and evidence path above before closing this window.
  pause
)

for %%# in (%SAS_RC%) do endlocal & exit /b %%#
