@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - Cybernet Deployment Readiness

if /I "%~1"=="Help" goto help_ok
if /I "%~1"=="-h" goto help_ok
if /I "%~1"=="--help" goto help_ok
if /I "%~1"=="/?" goto help_ok

if "%~1"=="" goto help_error
if "%~2"=="" goto help_error
if not "%~3"=="" (
  echo ERROR: Provide Probe and one explicit authorized Cybernet hostname or FQDN.
  goto help_error
)
if /I not "%~1"=="Probe" (
  echo ERROR: Mode must be Probe.
  goto help_error
)

echo.
echo Read-only one-target readiness probe.
echo No task creation, software installation, target mutation, or restart will occur.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-SasCybernetDeploymentReadiness.ps1" -ComputerName "%~2" -AllowNetworkActivity
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Cybernet readiness stopped with exit code %EXITCODE%. Review the emitted evidence before retrying or broadening the probe.
endlocal & exit /b %EXITCODE%

:help_ok
call :print_help
exit /b 0

:help_error
call :print_help
exit /b 2

:print_help
echo SysAdminSuite Cybernet Software Deployment Readiness
echo.
echo Usage:
echo   Probe-CybernetSoftware.cmd Probe CYBERNET-HOST-OR-FQDN
echo   sas cybernet Probe CYBERNET-HOST-OR-FQDN
echo.
echo The probe performs only the current deployment dependency chain:
echo   1. local approved Northwell network posture
echo   2. one authorized target DNS resolution
echo   3. CIFS Kerberos service ticket
echo   4. TCP 445
echo   5. ADMIN$ read authorization
echo   6. TCP 135 only after ADMIN$ is authorized
echo   7. Schedule service and one reserved nonexistent task query
echo.
echo It never probes WinRM, never uses broad transport discovery, and never mutates the target.
echo Success status: CYBERNET_DEPLOYMENT_READINESS_READY
echo Full deployment remains: sas cybernet Deploy CYBERNET-HOST-OR-FQDN
goto :eof
