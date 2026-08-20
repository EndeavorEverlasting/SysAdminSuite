@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bootstrap-SysAdminSuitePrinter.ps1" -RequiredCommit 5463c0ed3fedc4f9c5fe8048ead3cfc6bf2c434f %*
exit /b %ERRORLEVEL%
