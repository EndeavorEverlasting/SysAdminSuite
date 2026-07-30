@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - Cybernet Clinical Core Deployment

if /I "%~1"=="Help" goto help_ok
if /I "%~1"=="-h" goto help_ok
if /I "%~1"=="--help" goto help_ok
if /I "%~1"=="/?" goto help_ok

if "%~1"=="" goto help_error
if "%~2"=="" goto help_error
if not "%~3"=="" (
  echo ERROR: Provide one mode and one explicit authorized Cybernet hostname or FQDN.
  goto help_error
)

if /I "%~1"=="Plan" goto plan
if /I "%~1"=="Deploy" goto deploy
echo ERROR: Mode must be Plan or Deploy.
goto help_error

:plan
powershell.exe -NoLogo -NoProfile -File "%SCRIPT_DIR%scripts\Invoke-SasCybernetClinicalCoreDeployment.ps1" -Mode Plan -ComputerName "%~2"
goto done

:deploy
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1" -ComputerName "%~2" -AllowTargetMutation -ConfirmDeployment
goto done

:help_ok
call :print_help
exit /b 0

:help_error
call :print_help
exit /b 2

:print_help
echo SysAdminSuite Cybernet Clinical Core Deployment
echo.
echo Usage:
echo   Deploy-CybernetClinicalCore.cmd Plan CYBERNET-HOST
echo   Deploy-CybernetClinicalCore.cmd Deploy CYBERNET-HOST
echo.
echo Plan retains the legacy non-mutating controller dry run.
echo Deploy uses the Windows-native profiled lane: no Git Bash or Python dependency.
echo It stages and hash-verifies the five approved clinical-core applications, executes them once as SYSTEM,
echo captures before/after Cybernet profile state including observational Imprivata and AutoLogon state,
echo and removes run-scoped staging after result retrieval.
echo.
echo AutoLogon is NOT included, changed, repaired, or enabled by Deploy.
echo Imprivata is observed only and is never installed, removed, or configured by this lane.
echo No reboot is performed.
exit /b 0

:done
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Clinical-core deployment finished with exit code %EXITCODE%. Review the emitted evidence before retrying.
endlocal & exit /b %EXITCODE%
