@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_CLOCK=%~dp0GetInfo\Open-KronosClockBatch.ps1"
if not exist "%SAS_CLOCK%" (
  echo BLOCKED: Kronos clock batch entrypoint is missing from this release.
  exit /b 2
)
if not exist "%SAS_PS%" (
  echo BLOCKED: Windows PowerShell 5.1 is unavailable.
  exit /b 2
)
"%SAS_PS%" -NoLogo -NoProfile -File "%SAS_CLOCK%"
set "SAS_RESULT=%ERRORLEVEL%"
if not "%SAS_RESULT%"=="0" pause
exit /b %SAS_RESULT%
