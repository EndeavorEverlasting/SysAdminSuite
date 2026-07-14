@echo off
setlocal
if not "%~1"=="" (
  echo This launcher accepts no arguments. It inspects the latest validated deployment evidence.
  exit /b 2
)
set "ROOT=%~dp0"
where pwsh.exe >nul 2>&1
if %errorlevel%==0 (
  pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Show-SasValidatedSoftwareDeploymentResult.ps1" -RequireCompleted
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Show-SasValidatedSoftwareDeploymentResult.ps1" -RequireCompleted
)
exit /b %errorlevel%
