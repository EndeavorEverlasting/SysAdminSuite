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
  echo ERROR: Provide exactly one explicit authorized Cybernet hostname or FQDN.
  echo.
  goto help_error
)
if not "%~3"=="" (
  echo ERROR: This launcher accepts one mode and one target only.
  echo Use Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 for an approved CSV batch after pilot acceptance.
  exit /b 2
)

if /I "%MODE%"=="Pilot" goto pilot
if /I "%MODE%"=="Plan" goto plan
if /I "%MODE%"=="DryRun" goto plan
if /I "%MODE%"=="Apply" goto apply
if /I "%MODE%"=="Validate" goto validate
echo ERROR: Mode must be Pilot, Plan, DryRun, Apply, or Validate.
echo.
goto help_error

:pilot
powershell.exe -NoProfile -File "%SCRIPT_DIR%Hardware\Cybernet\Invoke-CybernetClientPilot.ps1" -ComputerName "%TARGET%" -OpenResults
goto done

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
echo This launcher accepts one explicit authorized Cybernet target only.
echo Pilot accepts the short hostname and resolves one canonical FQDN automatically.
echo.
echo Usage:
echo Preferred one-target pilot:
echo   Double-click Run-CybernetLiveCert.cmd and enter the short Cybernet hostname.
echo   Or: Run-CybernetClientConfiguration.cmd Pilot CYBERNET-HOST
echo.
echo Other modes:
echo   Run-CybernetClientConfiguration.cmd Plan CYBERNET-HOST
echo   Run-CybernetClientConfiguration.cmd DryRun CYBERNET-HOST
echo   Run-CybernetClientConfiguration.cmd Apply CYBERNET-HOST
echo   Run-CybernetClientConfiguration.cmd Validate CYBERNET-HOST
echo   Run-CybernetClientConfiguration.cmd Help
echo.
echo Modes:
echo   Pilot     Recommended first production surface for one authorized Cybernet hostname.
echo             Resolves the FQDN, runs the deployment dry run, bounded read-only transport
echo             preflight, harmless live cert, production confirmation, Apply, and Validate.
echo             Any unresolved, ambiguous, or failed gate stops before higher-impact work.
echo   Plan      Validate the profile, create the hardware plan, and run the approved
echo             six-package software controller in dry-run mode. No target or share contact.
echo   DryRun    Alias for Plan.
echo   Apply     Apply and validate hardware, install the approved package set with
echo             AutoLogon last, validate hardware again, then require technician acceptance.
echo   Validate  Recheck hardware without changing the target or reinstalling software.
echo.
echo Pilot success status:
echo   PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED
echo.
echo Other success statuses:
echo   PLAN_READY
echo   APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED
echo   HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED
echo.
echo Evidence:
echo   survey\output\cybernet_live_cert\cybernet-live-cert-*
echo   OPEN-ME-CYBERNET-LIVE-CERT.txt
echo   cybernet_live_cert_summary.json
echo   cybernet_client_configuration_summary.json
echo   technician_software_acceptance.txt
echo.
echo Safety:
echo   Cybernet profile only. Never use for a shared or normal user-login workstation.
echo   The Pilot gate requires Plan and harmless live-cert proof before production Apply.
echo   The workflow never reboots a target or repairs COM ports remotely.
echo   Do not place passwords in commands. Do not bypass a failed or ambiguous gate.
echo   Use Hardware\Cybernet\Invoke-CybernetClientConfiguration.ps1 for approved CSV batches.
echo.
echo Guides:
echo   docs\tutorials\CYBERNET_CLIENT_PILOT.md
echo   docs\tutorials\CYBERNET_CLIENT_CONFIGURATION.md
echo   docs\tutorials\CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md
exit /b 0

:done
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Client configuration finished with exit code %EXITCODE%. Review generated evidence before retrying.
endlocal & exit /b %EXITCODE%
