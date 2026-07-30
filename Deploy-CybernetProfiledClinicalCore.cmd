@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
if "%~1"=="" goto help
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1" -ComputerName "%~1" -AllowTargetMutation -ConfirmDeployment
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Profiled clinical-core deployment finished with exit code %EXITCODE%. Preserve emitted evidence before any retry.
endlocal & exit /b %EXITCODE%

:help
echo Usage: Deploy-CybernetProfiledClinicalCore.cmd CYBERNET-HOST
echo Deploys the five clinical-core applications without AutoLogon, captures before/after Cybernet profile state,
echo records Imprivata as observational/external state only, performs no reboot, and cleans run-scoped staging.
exit /b 2
