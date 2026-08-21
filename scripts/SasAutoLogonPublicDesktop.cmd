@echo off
setlocal EnableExtensions DisableDelayedExpansion
title SysAdminSuite - AutoLogon Remote
cls

echo ================================================================
echo  SYSADMINSUITE - AUTOLOGON REMOTE
echo ================================================================
echo  Uses the installed SysAdminSuite network-aware AutoLogon route.
echo  No target is stored in this launcher. Enter one authorized host.
echo ================================================================
echo.

set "SAS_AUTOLOGON_ENTRYPOINT=%ProgramData%\SysAdminSuite\bin\Invoke-SasNetworkAwareField.ps1"
if not exist "%SAS_AUTOLOGON_ENTRYPOINT%" (
  echo ERROR: Machine-wide SysAdminSuite launcher is missing.
  echo Run the approved SysAdminSuite refresh/readiness installation first.
  set "SAS_EXIT=10"
  goto finish
)

set "SAS_AUTOLOGON_TARGET="
set /p "SAS_AUTOLOGON_TARGET=Authorized hostname or FQDN: "
if not defined SAS_AUTOLOGON_TARGET (
  echo ERROR: No target entered.
  set "SAS_EXIT=2"
  goto finish
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$t=[string]$env:SAS_AUTOLOGON_TARGET; if($t -notmatch '^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$'){Write-Host 'ERROR: Target must be a hostname or FQDN.' -ForegroundColor Red; exit 2}; & $env:SAS_AUTOLOGON_ENTRYPOINT 'autologon' 'Remote' $t; $e=$global:LASTEXITCODE; if($null -eq $e){$e=1}; exit [int]$e"
set "SAS_EXIT=%ERRORLEVEL%"

:finish
if not "%SAS_EXIT%"=="0" (
  echo.
  echo AutoLogon Remote did not finish successfully.
  echo Preserve the SysAdminSuite evidence shown by the command; do not retry blindly.
  echo.
  pause
)
endlocal & exit /b %SAS_EXIT%
