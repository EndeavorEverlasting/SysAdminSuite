@echo off
setlocal EnableExtensions
rem Sibling bootstrap resolves the registered machine-neutral canonical checkout
rem and forces the approved Admin Box developer-tools role; never a PTop disguise.
if not exist "%~dp0scripts\Start-SasAdminBoxAndroidToolchain.ps1" (
  echo BLOCK: Repository-owned Admin Box Android toolchain bootstrap is required.
  exit /b 2
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-SasAdminBoxAndroidToolchain.ps1" %*
exit /b %ERRORLEVEL%
