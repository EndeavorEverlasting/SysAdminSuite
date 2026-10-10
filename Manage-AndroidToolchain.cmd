@echo off
setlocal EnableExtensions
rem Resolve the machine-neutral prepared runtime; never a named user's checkout.
if not exist "C:\SASAL\scripts\Invoke-SasAndroidToolchain.ps1" (
  echo BLOCK: Current prepared SysAdminSuite runtime is required at C:\SASAL.
  exit /b 2
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\SASAL\scripts\Invoke-SasAndroidToolchain.ps1" %*
exit /b %ERRORLEVEL%
