@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
rem Compatibility note: older bootstrap floor was -RequiredCommit 5463c0ed3fedc4f9c5fe8048ead3cfc6bf2c434f.
rem Current floor includes active-user materialization so a successful map is visible in an existing session.
"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bootstrap-SysAdminSuitePrinter.ps1" -RequiredCommit 66d38dd45881692303f77267e29e4fa44b4a9351 %*
exit /b %ERRORLEVEL%
