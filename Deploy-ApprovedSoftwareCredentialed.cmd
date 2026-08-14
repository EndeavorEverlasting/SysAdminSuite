@echo off
setlocal
set "SCRIPT=%~dp0scripts\Invoke-SasCredentialedApprovedSoftwareInstall.ps1"

if not exist "%SCRIPT%" (
  echo Missing credentialed deployment script: %SCRIPT%
  pause
  exit /b 2
)

if "%~1"=="" (
  echo Usage:
  echo   Deploy-ApprovedSoftwareCredentialed.cmd TARGET_FQDN PACKAGE_ID
  echo.
  echo Qualification-only example:
  echo   powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -ComputerName TARGET_FQDN -PackageId autologon -QualificationOnly -ConfirmDeployment
  echo.
  echo Normal deployment example:
  echo   powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -ComputerName TARGET_FQDN -PackageId bca -ConfirmDeployment
  pause
  exit /b 2
)

if "%~2"=="" (
  echo PACKAGE_ID is required.
  pause
  exit /b 2
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -ComputerName "%~1" -PackageId "%~2" -ConfirmDeployment
set "RC=%ERRORLEVEL%"

echo.
echo Credentialed WinRM deployment returned exit code %RC%.
echo Evidence pointer: %%LOCALAPPDATA%%\SysAdminSuite\last-credentialed-winrm-run.json
echo The credential was runtime-only and was not written to evidence.
echo.
pause
exit /b %RC%
