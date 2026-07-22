@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - Cybernet Client Configuration

if "%~1"=="" (
  echo SysAdminSuite Cybernet Client Configuration
  echo.
  echo Plan one authorized pilot without target contact:
  echo   Run-CybernetClientConfiguration.cmd Plan CYBERNET-HOST
  echo.
  echo Apply hardware preferences and the approved six-package software set:
  echo   Run-CybernetClientConfiguration.cmd Apply CYBERNET-HOST
  echo.
  echo Validate hardware without changing the target:
  echo   Run-CybernetClientConfiguration.cmd Validate CYBERNET-HOST
  echo.
  echo The workflow never reboots a target or repairs COM ports remotely.
  exit /b 2
)

set "MODE=%~1"
set "TARGET=%~2"
if "%TARGET%"=="" (
  echo ERROR: Provide exactly one explicit authorized Cybernet hostname.
  exit /b 2
)
if not "%~3"=="" (
  echo ERROR: This launcher accepts one mode and one hostname only.
  echo Use Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 for an approved CSV batch after pilot acceptance.
  exit /b 2
)

if /I "%MODE%"=="Plan" goto plan
if /I "%MODE%"=="Apply" goto apply
if /I "%MODE%"=="Validate" goto validate
echo ERROR: Mode must be Plan, Apply, or Validate.
exit /b 2

:plan
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1" -Mode Plan -ComputerName "%TARGET%"
goto done

:apply
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1" -Mode Apply -ComputerName "%TARGET%" -AllowTargetMutation
goto done

:validate
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1" -Mode Validate -ComputerName "%TARGET%"

:done
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Client configuration finished with exit code %EXITCODE%. Review survey\output\cybernet_hardware.
endlocal & exit /b %EXITCODE%
