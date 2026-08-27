@echo off
setlocal
set "ROOT=%~dp0"
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%recovery\windows\Get-SasWindowsRecoveryEvidence.ps1" %*
  exit /b %ERRORLEVEL%
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%recovery\windows\Get-SasWindowsRecoveryEvidence.ps1" %*
exit /b %ERRORLEVEL%
