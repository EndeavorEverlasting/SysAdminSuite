@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title SysAdminSuite - Cybernet Live Cert

set "TARGET=%~1"
if not defined TARGET (
  echo.
  echo SysAdminSuite Cybernet Live Cert
  echo ---------------------------------
  echo Enter the authorized Cybernet hostname from the assignment or device label.
  echo Use the short hostname. The script resolves and proves the FQDN automatically.
  echo.
  set /p "TARGET=Cybernet hostname: "
)

if not defined TARGET (
  echo.
  echo ERROR: No hostname was entered. Nothing was contacted or changed.
  echo.
  pause
  exit /b 2
)

if not "%~2"=="" (
  echo.
  echo ERROR: This launcher accepts one hostname only.
  echo.
  pause
  exit /b 2
)

echo.
echo Target input: %TARGET%
echo The launcher will resolve one canonical FQDN, run the deployment dry run,
echo run bounded live certification, and ask separately before production.
echo Any unresolved, ambiguous, or failed gate stops the workflow.
echo.

powershell.exe -NoProfile -File "%~dp0Hardware\Cybernet\Invoke-CybernetClientPilot.ps1" -ComputerName "%TARGET%" -OpenResults
set "EXITCODE=%ERRORLEVEL%"

echo.
if "%EXITCODE%"=="0" (
  echo Cybernet live-cert launcher completed. Review the opened handoff and evidence folder.
) else (
  echo Cybernet live-cert launcher stopped with exit code %EXITCODE%.
  echo Review the opened ACTION_REQUIRED handoff. Do not bypass or blindly retry the failed gate.
)
echo.
pause
endlocal & exit /b %EXITCODE%
