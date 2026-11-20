@echo off
setlocal
set "SCRIPT=%~dp0scripts\Get-SasDockIncident.ps1"
if not exist "%SCRIPT%" (
    echo Dock incident collector is missing from this SysAdminSuite checkout.
    exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %ERRORLEVEL%
