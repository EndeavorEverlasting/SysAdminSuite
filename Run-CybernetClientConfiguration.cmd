@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - Cybernet Client Configuration

if /I "%~1"=="Help" goto help_ok
if /I "%~1"=="-h" goto help_ok
if /I "%~1"=="--help" goto help_ok
if /I "%~1"=="/?" goto help_ok
if "%~1"=="" goto help_error

set "MODE=%~1"
set "TARGET=%~2"
if "%TARGET%"=="" (
  echo ERROR: Provide exactly one explicit authorized Cybernet hostname.
  echo.
  goto help_error
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
echo.
goto help_error

:plan
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1" -Mode Plan -ComputerName "%TARGET%"
goto done

:apply
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1" -Mode Apply -ComputerName "%TARGET%" -AllowTargetMutation
goto done

:validate
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1" -Mode Validate -ComputerName "%TARGET%"
goto done

:help_ok
call :print_help
exit /b 0

:help_error
call :print_help
exit /b 2

:print_help
echo SysAdminSuite Cybernet Client Configuration
echo.
echo Run from the SysAdminSuite repository root on an approved Windows admin controller.
echo This launcher accepts one explicit authorized hostname only.
echo.
echo Usage:
echo   Run-CybernetClientConfiguration.cmd Plan CYBERNET-HOST
echo   Run-CybernetClientConfiguration.cmd Apply CYBERNET-HOST
echo   Run-CybernetClientConfiguration.cmd Validate CYBERNET-HOST
echo   Run-CybernetClientConfiguration.cmd Help
echo.
echo Modes:
echo   Plan      Validate the profile, create the hardware plan, and run the approved
echo             six-package software controller in dry-run mode. No target or share contact.
echo   Apply     Apply and validate hardware, install the approved package set with
echo             AutoLogon last, validate hardware again, then require technician acceptance.
echo   Validate  Recheck hardware without changing the target or reinstalling software.
echo.
echo Success statuses:
echo   PLAN_READY
echo   APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED
echo   HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED
echo.
echo Evidence:
echo   survey\output\cybernet_hardware\client-configuration-*
echo   cybernet_client_configuration_summary.json
echo   operator_handoff.txt
echo   technician_software_acceptance.txt
echo.
echo Safety:
echo   The workflow never reboots a target or repairs COM ports remotely.
echo   Do not place passwords in commands. Run Plan before Apply.
echo   Use Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 for approved CSV batches.
echo.
echo Guides:
echo   docs\tutorials\CYBERNET_CLIENT_CONFIGURATION.md
echo   docs\tutorials\CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md
exit /b 0

:done
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Client configuration finished with exit code %EXITCODE%. Review survey\output\cybernet_hardware.
endlocal & exit /b %EXITCODE%
