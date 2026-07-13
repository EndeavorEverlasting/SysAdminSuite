@echo off
setlocal EnableExtensions

if "%~1"=="" (
  echo Usage: %~nx0 ^<runtime-proof-config.json^>
  echo.
  echo Run this launcher inside the actual AutoLogon desktop session.
  echo Use a site-approved config copied from docs\examples\autologon-runtime-proof.example.json.
  exit /b 2
)

set "CONFIG_PATH=%~f1"
set "PS_SCRIPT=%~dp0Invoke-SasAutoLogonTechnicianRuntimeProof.ps1"

if not exist "%PS_SCRIPT%" (
  echo ERROR: Repo-owned PowerShell runner not found: %PS_SCRIPT%
  exit /b 3
)

if not exist "%CONFIG_PATH%" (
  echo ERROR: Runtime proof config not found: %CONFIG_PATH%
  exit /b 4
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -ConfigPath "%CONFIG_PATH%"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
  echo Runtime proof runner completed. Review the evidence directory from the config.
) else (
  echo Runtime proof runner failed with exit code %EXIT_CODE%.
  echo Review runtime-proof-summary.json and runtime-proof-chain.log in the evidence directory.
)

if not "%SAS_RUNTIME_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%
