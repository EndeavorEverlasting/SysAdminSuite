@echo off
setlocal
set "SCRIPT=%~dp0scripts\Invoke-SasCredentialedApprovedSoftwareInstall.ps1"

if not exist "%SCRIPT%" (
  echo Missing credentialed deployment script: %SCRIPT%
  pause
  exit /b 2
)

if "%~1"=="" goto :usage
if "%~2"=="" goto :usage

set "MODE=%~3"
set "EXTRA="
if not "%MODE%"=="" (
  if /I not "%MODE%"=="QUALIFY" (
    echo Unsupported mode: %MODE%
    goto :usage
  )
  set "EXTRA=-QualificationOnly -EquipmentProfile Cybernet"
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -ComputerName "%~1" -PackageId "%~2" %EXTRA% -ConfirmDeployment
set "RC=%ERRORLEVEL%"

echo.
echo Credentialed WinRM lane returned exit code %RC%.
echo Evidence pointer: %%LOCALAPPDATA%%\SysAdminSuite\last-credentialed-winrm-run.json
echo Credentials remain runtime-only and are never written to evidence.
echo No fallback to another transport is attempted by this launcher.
echo.
pause
exit /b %RC%

:usage
echo Usage:
echo   Deploy-ApprovedSoftwareCredentialed.cmd TARGET_FQDN PACKAGE_ID
echo   Deploy-ApprovedSoftwareCredentialed.cmd TARGET_FQDN autologon QUALIFY
echo.
echo QUALIFY explicitly selects the Cybernet AutoLogon qualification lane.
echo The package catalog must already contain an independently reviewed SHA-256 pin
echo and the corresponding credentialed WinRM opt-in before target contact is allowed.
echo.
pause
exit /b 2
