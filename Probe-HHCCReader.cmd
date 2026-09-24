@echo off
setlocal EnableExtensions EnableDelayedExpansion
title SysAdminSuite - H&H CC Reader Read-Only Probe
cls

if "%~1"=="" goto usage

set "SAS_EXIT=1"

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER READ-ONLY PROBE
echo ================================================================
echo  Target: %~1
if not "%~2"=="" echo  Expected MAC supplied: yes
echo.
echo  Scope: one explicit IPv4 target; read-only network observation.
echo  No reader configuration, payment action, reset, or firmware mutation.
echo ================================================================
echo.

if defined SAS_HH_CC_READER_REFRESHED goto probe

if not exist "%~dp0scripts\Invoke-SasNetworkAwareField.ps1" (
    echo ERROR: Canonical SysAdminSuite refresh entrypoint is missing beside this CMD.
    echo Use the current machine-neutral SysAdminSuite bootstrap before probing.
    set "SAS_EXIT=1"
    goto finish
)

echo Proving current SysAdminSuite main before any target contact...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasNetworkAwareField.ps1" refresh
set "SAS_EXIT=!ERRORLEVEL!"
if not "!SAS_EXIT!"=="0" goto finish

if not exist "C:\SASAL\Probe-HHCCReader.cmd" (
    echo ERROR: Refresh completed but C:\SASAL\Probe-HHCCReader.cmd is missing.
    set "SAS_EXIT=1"
    goto finish
)

set "SAS_HH_CC_READER_REFRESHED=1"
if "%~2"=="" (
    call "C:\SASAL\Probe-HHCCReader.cmd" "%~1"
) else (
    call "C:\SASAL\Probe-HHCCReader.cmd" "%~1" "%~2"
)
set "SAS_EXIT=!ERRORLEVEL!"
goto finish

:probe
if not exist "%~dp0scripts\Invoke-SasHhCcReaderProbe.ps1" (
    echo ERROR: Refreshed H^&H CC-reader probe is missing.
    set "SAS_EXIT=1"
    goto finish
)

if "%~2"=="" (
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasHhCcReaderProbe.ps1" -IPAddress "%~1"
) else (
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasHhCcReaderProbe.ps1" -IPAddress "%~1" -ExpectedMac "%~2"
)
set "SAS_EXIT=!ERRORLEVEL!"
goto finish

:usage
echo ================================================================
echo  SYSADMINSUITE H^&H CC READER READ-ONLY PROBE
echo ================================================================
echo  Usage:
echo    Probe-HHCCReader.cmd IPV4 [EXPECTED-MAC]
echo.
echo  Example with documentation-only TEST-NET data:
echo    Probe-HHCCReader.cmd 192.0.2.10 AA-BB-CC-DD-EE-FF
echo.
echo  Supply one explicit IPv4 address only. CIDRs, ranges, wildcards,
echo  host discovery, and scanner/generator behavior are outside this lane.
echo ================================================================
set "SAS_EXIT=2"

:finish
if not "!SAS_EXIT!"=="0" (
    echo.
    echo H^&H CC-reader probe did not finish successfully.
    echo No failed stage may be promoted to reader reachability or identity proof.
)
endlocal & exit /b %SAS_EXIT%
