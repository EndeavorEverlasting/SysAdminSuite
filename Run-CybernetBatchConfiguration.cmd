@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
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
  echo Apply requires an interactive high-impact confirmation. COM repair is never performed remotely.
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
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetBatchConfiguration.ps1" -Mode Apply -ComputerName "%TARGET%" -AllowTargetMutation
goto done

:validate
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetBatchConfiguration.ps1" -Mode Validate -ComputerName "%TARGET%"

:done
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Cybernet batch finished with exit code %EXITCODE%. Review survey\output\cybernet_hardware.
endlocal & exit /b %EXITCODE%
