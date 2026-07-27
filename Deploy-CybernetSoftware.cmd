@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - Cybernet Software Deployment

if /I "%~1"=="Help" goto help_ok
if /I "%~1"=="-h" goto help_ok
if /I "%~1"=="--help" goto help_ok
if /I "%~1"=="/?" goto help_ok

if "%~1"=="" goto help_error
if "%~2"=="" goto help_error
if not "%~3"=="" (
  echo ERROR: Provide Deploy and one explicit authorized Cybernet hostname or FQDN.
  goto help_error
)

if /I "%~1"=="Deploy" goto deploy
echo ERROR: Mode must be Deploy.
goto help_error

:deploy
powershell.exe -NoLogo -NoProfile -File "%SCRIPT_DIR%scripts\Invoke-SasCybernetSoftwareDeployment.ps1" -ComputerName "%~2" -AllowTargetMutation -ConfirmDeployment
goto done

:help_ok
call :print_help
exit /b 0

:help_error
call :print_help
exit /b 2

:print_help
echo SysAdminSuite Cybernet Software Deployment
echo.
echo Usage:
echo   Deploy-CybernetSoftware.cmd Deploy CYBERNET-HOST
echo.
echo Deploy performs the complete current field software transaction:
echo   1. five approved clinical-core applications
echo   2. AutoLogon as the final software step through Kerberos/S4U
echo   3. automatic restart of the target
echo   4. bounded observation that the target left and returned on the proven SMB path
echo.
echo Success status:
echo   CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
echo.
echo The deployment command does not require a separate fixture, live-cert, or runtime-proof loop.
echo Runtime proof remains available when explicitly requested, but it is not required for deployment completion.
exit /b 0

:done
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Cybernet software deployment finished with exit code %EXITCODE%. Review the emitted evidence before retrying.
endlocal & exit /b %EXITCODE%
