@echo off
setlocal EnableExtensions
rem Sibling bootstrap resolves the registered machine-neutral canonical checkout.
if not exist "%~dp0scripts\Start-SasAndroidToolchain.ps1" (
  echo BLOCK: Repository-owned Android toolchain bootstrap is required.
  exit /b 2
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-SasAndroidToolchain.ps1" %*
exit /b %ERRORLEVEL%
