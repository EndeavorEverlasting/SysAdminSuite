@echo off
setlocal
set "ROOT=%~dp0"
where pwsh.exe >nul 2>&1
if errorlevel 1 goto use_windows_powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%recovery\windows\Get-SasWindowsRecoveryEvidence.ps1" %*
exit /b %ERRORLEVEL%

:use_windows_powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%recovery\windows\Get-SasWindowsRecoveryEvidence.ps1" %*
exit /b %ERRORLEVEL%
