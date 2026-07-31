@echo off
setlocal EnableExtensions
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
echo NETWORK REQUIRED: PROTECTED NORTHWELL
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Test-SasCybernetClinicalCoreSources.ps1"
if errorlevel 1 goto done
powershell.exe -NoLogo -NoProfile -File "%SCRIPT_DIR%scripts\Invoke-SasCybernetClinicalCoreDeployment.ps1" -Mode Plan -ComputerName "%~2"
goto done

:deploy
call "%SCRIPT_DIR%Deploy-CybernetProfiledClinicalCore.cmd" "%~2"
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
echo Deploy routes through the same stateful Windows-native transaction as sas cybernet Core HOST.
echo It owns exact prior-run recovery, source preflight before new staging, SYSTEM execution,
echo before/after AutoLogon + Imprivata profile evidence, no reboot, and verified run-scoped cleanup.
echo AutoLogon is NOT included. Imprivata is observational/external only.
exit /b 0

:done
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Clinical-core operation finished with exit code %EXITCODE%. Use sas context or sas next before retrying.
for %%# in (%EXITCODE%) do endlocal ^& exit /b %%#