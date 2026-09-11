@echo off
setlocal EnableExtensions EnableDelayedExpansion
title SysAdminSuite - Cybernet Identity Probe
cls

if "%~1"=="" goto usage

set "SAS_EXIT=1"

echo ================================================================
echo  SYSADMINSUITE CYBERNET IDENTITY PROBE
echo ================================================================
echo  Question: Is each explicit candidate a Windows client workstation,
echo  and can it return model + serial for approved Cybernet-reference comparison?
echo.
echo  Evidence ladder:
echo    135 + 445 open       = metadata candidate only
echo    ProductType = 1      = Windows client workstation only
echo    model + BIOS serial  = observed hardware identity facts
echo    Cybernet confirmed   = only after approved reference comparison
echo ================================================================
echo.

if defined SAS_CYBERNET_PROBE_REFRESHED goto probe

rem Never trust a source/sealed CMD as current merely because it exists.
rem The canonical refresh performs remote Git only in the Guest/Internet sync cache,
rem derives fresh field-ready content from origin/main, restores network posture, and
rem reseals C:\SASAL before this launcher re-enters the refreshed CMD.
if not exist "%~dp0scripts\Invoke-SasNetworkAwareField.ps1" (
    echo ERROR: Canonical SysAdminSuite refresh entrypoint is missing beside this CMD.
    echo Run a current machine-neutral SysAdminSuite bootstrap before probing.
    set "SAS_EXIT=1"
    goto finish
)

echo Proving current SysAdminSuite main before any target contact...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasNetworkAwareField.ps1" refresh
set "SAS_EXIT=!ERRORLEVEL!"
if not "!SAS_EXIT!"=="0" goto finish

if not exist "C:\SASAL\Probe-Cybernet.cmd" (
    echo ERROR: Refresh completed but the sealed runtime does not contain C:\SASAL\Probe-Cybernet.cmd.
    set "SAS_EXIT=1"
    goto finish
)

set "SAS_CYBERNET_PROBE_REFRESHED=1"
call "C:\SASAL\Probe-Cybernet.cmd" %*
set "SAS_EXIT=!ERRORLEVEL!"
goto finish

:probe
if not exist "%~dp0survey\sas-cybernet-canary.ps1" (
    echo ERROR: Refreshed Cybernet canary is missing: %~dp0survey\sas-cybernet-canary.ps1
    set "SAS_EXIT=1"
    goto finish
)

echo Running one bounded identity canary against the explicit candidate list...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0survey\sas-cybernet-canary.ps1" %*
set "SAS_EXIT=!ERRORLEVEL!"
goto finish

:usage
echo ================================================================
echo  SYSADMINSUITE CYBERNET IDENTITY PROBE
echo ================================================================
echo  Usage: Probe-Cybernet.cmd HOST01 [HOST02 ...]
echo.
echo  Up to five explicit hostname/FQDN/IP candidates are accepted by the canary.
echo  CIDRs, ranges, wildcards, and subnet discovery are refused.
echo.
echo  The CMD refreshes origin/main through the canonical Guest/Internet sync
 echo  transaction before any target contact, then runs the refreshed sealed canary.
echo ================================================================
set "SAS_EXIT=2"

:finish
if not "!SAS_EXIT!"=="0" (
    echo.
    echo Cybernet identity probe did not finish successfully.
    echo No failed stage may be promoted to Cybernet identity proof.
)
endlocal & exit /b %SAS_EXIT%
