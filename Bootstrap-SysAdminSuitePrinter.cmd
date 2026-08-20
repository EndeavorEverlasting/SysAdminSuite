@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bootstrap-SysAdminSuitePrinter.ps1" -RequiredCommit 66d38dd45881692303f77267e29e4fa44b4a9351 %*
exit /b %ERRORLEVEL%
