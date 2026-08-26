@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "SCRIPT_DIR=%~dp0"
set "SEALED_RUNTIME=C:\SASAL"
set "SEALED_BOOTSTRAP=%SEALED_RUNTIME%\Bootstrap-SysAdminSuiteCybernetSoftware.cmd"
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
if not exist "%SEALED_BOOTSTRAP%" (
  echo ERROR: The canonical sealed Cybernet deployment bootstrap is missing:
  echo   %SEALED_BOOTSTRAP%
  echo.
  echo This checkout is not deployment authority. No target contact or mutation was started.
  echo NETWORK REQUIRED: GUEST / INTERNET
  echo Return to Guest/Internet with VPN disconnected and run: sas refresh
  echo If the installed sas command is stale or unavailable, use Bootstrap-SysAdminSuiteFieldRuntime.cmd from a fresh current-main checkout.
  exit /b 20
)
echo Cybernet deployment authority: %SEALED_RUNTIME%
echo Launcher checkout is informational only: %SCRIPT_DIR%
rem The sealed bootstrap owns -AllowTargetMutation -ConfirmDeployment only after manifest and full runtime-seal validation.
call "%SEALED_BOOTSTRAP%" "%~2"
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
echo   Deploy-CybernetSoftware.cmd Deploy CYBERNET-HOST-OR-FQDN
echo   sas cybernet Deploy CYBERNET-HOST-OR-FQDN
echo.
echo Protected deployment always enters the sealed C:\SASAL runtime. The checkout containing this launcher is never target-mutation authority.
echo If C:\SASAL is missing or stale, return to Guest/Internet with VPN disconnected and run sas refresh.
echo Admin-box recovery from a stale or unknown checkout is documented in:
echo   START-HERE-ADMIN-BOX-SOFTWARE-DEPLOYMENT.md
echo.
echo Deploy performs the complete current field software transaction:
echo   1. bounded low-noise Kerberos SMB plus Task Scheduler readiness
echo   2. five approved clinical-core applications
echo   3. AutoLogon as the final software step through Kerberos/S4U
echo   4. automatic restart of the target
echo   5. bounded observation that the target left and returned on the proven SMB path
echo.
echo The readiness gate stops before mutation if DNS, CIFS ticket, TCP 445, ADMIN$, TCP 135,
echo Schedule service, or the reserved task query is not ready. It never broadens to WinRM.
echo.
echo Optional read-only troubleshooting command:
echo   sas cybernet Probe CYBERNET-HOST-OR-FQDN
echo.
echo Success status:
echo   CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
echo.
echo The deployment command does not require a separate fixture, live-cert, runtime-proof,
echo or manual probe loop. Runtime proof remains available when explicitly requested, but
echo it is not required for deployment completion.
exit /b 0

:done
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Cybernet software deployment finished with exit code %EXITCODE%. Run sas evidence Cybernet Open and review the emitted evidence before retrying.
endlocal & exit /b %EXITCODE%
