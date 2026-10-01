@echo off
setlocal EnableExtensions EnableDelayedExpansion
title SysAdminSuite - H^&H CC Reader Endpoint Correlation
cls

set "SAS_EXIT=1"

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER ENDPOINT CORRELATION
echo ================================================================
echo  Scope: one explicit reader, one explicit endpoint, one TCP port.
echo  A non-secret approval/evidence reference is required.
echo  Read-only correlation only; no discovery sweep or target mutation.
echo ================================================================
echo.

if defined SAS_HH_CC_READER_ENDPOINT_REFRESHED goto probe

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

if not exist "C:\SASAL\Probe-HHCCReaderEndpoint.cmd" (
    echo ERROR: Refresh completed but C:\SASAL\Probe-HHCCReaderEndpoint.cmd is missing.
    set "SAS_EXIT=1"
    goto finish
)

set "SAS_HH_CC_READER_ENDPOINT_REFRESHED=1"
call "C:\SASAL\Probe-HHCCReaderEndpoint.cmd" "%~1" "%~2" "%~3" "%~4" "%~5"
set "SAS_EXIT=!ERRORLEVEL!"
goto finish

:probe
if not exist "%~dp0Probe-HHCCReader.cmd" (
    echo ERROR: Canonical H^&H CC-reader probe is missing.
    set "SAS_EXIT=1"
    goto finish
)
if not exist "%~dp0scripts\Invoke-SasHhCcReaderEndpointProbe.ps1" (
    echo ERROR: Refreshed H^&H CC-reader endpoint probe is missing.
    set "SAS_EXIT=1"
    goto finish
)

echo Validating endpoint correlation inputs before any target contact...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasHhCcReaderEndpointProbe.ps1" -ReaderIPAddress "%~1" -RemoteEndpoint "%~2" -RemotePort "%~3" -ApprovalRef "%~4" -ValidateOnly
set "SAS_EXIT=!ERRORLEVEL!"
if not "!SAS_EXIT!"=="0" (
    echo STOP: endpoint correlation input validation failed.
    goto finish
)

echo Running the canonical reader same-subnet/device gate first...
set "SAS_HH_CC_READER_REFRESHED=1"
call "%~dp0Probe-HHCCReader.cmd" "%~1" "%~5"
set "SAS_EXIT=!ERRORLEVEL!"
if not "!SAS_EXIT!"=="0" (
    echo STOP: canonical reader probe did not pass. Endpoint correlation is not interpreted.
    goto finish
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasHhCcReaderEndpointProbe.ps1" -ReaderIPAddress "%~1" -RemoteEndpoint "%~2" -RemotePort "%~3" -ApprovalRef "%~4"
set "SAS_EXIT=!ERRORLEVEL!"
goto finish

:finish
if not "!SAS_EXIT!"=="0" (
    echo.
    echo H^&H CC-reader endpoint correlation did not finish successfully.
    echo Usage:
    echo   Probe-HHCCReaderEndpoint.cmd READER_IPV4 REMOTE_ENDPOINT PORT APPROVAL_REF [EXPECTED-MAC]
    echo Documentation-only example:
    echo   Probe-HHCCReaderEndpoint.cmd 192.0.2.10 service.example.invalid 443 EVIDENCE-REF-001 AA-BB-CC-DD-EE-FF
    echo CIDRs, ranges, wildcards, port sweeps, and host discovery are refused.
    echo No failed stage may be promoted to endpoint reachability or ownership proof.
)
endlocal & exit /b %SAS_EXIT%
