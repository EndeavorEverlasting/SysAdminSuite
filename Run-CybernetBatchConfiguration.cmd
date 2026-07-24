@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "NETWORK_GATE=%SCRIPT_DIR%scripts\Confirm-SasNorthwellNetwork.ps1"
title SysAdminSuite - Cybernet Batch Configuration

if "%~1"=="" (
  echo SysAdminSuite Cybernet Hardware Batch
  echo.
  echo Plan one target:
  echo   Run-CybernetBatchConfiguration.cmd Plan CYBERNET-HOST
  echo.
  echo Apply one authorized pilot:
  echo   Run-CybernetBatchConfiguration.cmd Apply CYBERNET-HOST
  echo.
  echo Validate one target:
  echo   Run-CybernetBatchConfiguration.cmd Validate CYBERNET-HOST
  echo.
  echo Plan is local-only. Apply and Validate require approved Northwell network posture.
  echo If Guest is detected, the operator can switch/recheck or cancel before target contact.
  echo Apply still requires the existing interactive high-impact confirmation. COM repair is never performed remotely.
  exit /b 2
)

set "MODE=%~1"
set "TARGET=%~2"
if "%TARGET%"=="" (
  echo ERROR: Provide exactly one explicit Cybernet hostname.
  exit /b 2
)
if not "%~3"=="" (
  echo ERROR: This launcher accepts one mode and one hostname only. Use the tracked PowerShell entrypoint for an approved CSV batch.
  exit /b 2
)

if /I "%MODE%"=="Plan" goto plan
if /I "%MODE%"=="Apply" goto apply
if /I "%MODE%"=="Validate" goto validate
echo ERROR: Mode must be Plan, Apply, or Validate.
exit /b 2

:plan
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetBatchConfiguration.ps1" -Mode Plan -ComputerName "%TARGET%"
goto done

:apply
if not exist "%NETWORK_GATE%" (
  echo ERROR: Network gate was not found: %NETWORK_GATE%
  exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%NETWORK_GATE%" -Purpose "Cybernet Apply for %TARGET%"
set "NETWORK_EXIT=%ERRORLEVEL%"
if not "%NETWORK_EXIT%"=="0" (
  echo Cybernet Apply canceled or blocked before target mutation. Network gate exit code %NETWORK_EXIT%.
  exit /b %NETWORK_EXIT%
)
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetBatchConfiguration.ps1" -Mode Apply -ComputerName "%TARGET%" -AllowTargetMutation
goto done

:validate
if not exist "%NETWORK_GATE%" (
  echo ERROR: Network gate was not found: %NETWORK_GATE%
  exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%NETWORK_GATE%" -Purpose "Cybernet Validate for %TARGET%"
set "NETWORK_EXIT=%ERRORLEVEL%"
if not "%NETWORK_EXIT%"=="0" (
  echo Cybernet Validate canceled or blocked before target contact. Network gate exit code %NETWORK_EXIT%.
  exit /b %NETWORK_EXIT%
)
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetBatchConfiguration.ps1" -Mode Validate -ComputerName "%TARGET%"

:done
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Cybernet batch finished with exit code %EXITCODE%. Review survey\output\cybernet_hardware.
endlocal & exit /b %EXITCODE%
