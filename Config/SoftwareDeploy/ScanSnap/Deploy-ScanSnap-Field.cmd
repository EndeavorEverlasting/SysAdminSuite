@echo off
setlocal EnableExtensions
set "PS1=%~dp0Invoke-ScanSnapFieldDeployment.ps1"
if not exist "%PS1%" (
  echo SAS_SCANSNAP^|STATE=BLOCKED^|error=field_orchestrator_missing
  exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%ERRORLEVEL%"
echo SAS_SCANSNAP^|STATE=ENTRYPOINT_EXIT^|mode=deploy^|exit_code=%RC%
exit /b %RC%
