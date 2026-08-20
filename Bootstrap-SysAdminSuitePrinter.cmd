@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bootstrap-SysAdminSuitePrinter.ps1" %*
exit /b %ERRORLEVEL%
