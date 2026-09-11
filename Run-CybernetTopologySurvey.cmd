@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Cybernet Topology Survey

if /I "%~1"=="Help" goto help
if /I "%~1"=="-h" goto help
if /I "%~1"=="--help" goto help
if /I "%~1"=="/?" goto help

set "SAS_TOPOLOGY_ENTRYPOINT=TECHNICIAN_CMD"
set "SAS_ACTION=Status"
set "SAS_BUNDLE="

if /I "%~1"=="Export" set "SAS_ACTION=Export"
if /I "%~1"=="Import" (
  set "SAS_ACTION=Import"
  set "SAS_BUNDLE=%~2"
  if not defined SAS_BUNDLE (
    echo.
    echo Drag the bundle file you received onto this window, then press Enter.
    set /p "SAS_BUNDLE=Bundle file: "
  )
  if not defined SAS_BUNDLE (
    echo.
    echo ERROR: No bundle file was provided. Nothing was changed.
    echo.
    pause
    endlocal & exit /b 2
  )
)

echo.
echo SysAdminSuite Cybernet Topology Survey
echo --------------------------------------
echo This decides WHICH network locations have enough deployment evidence to
echo deserve a bounded, low-noise targeted pass. It does not decide what a
echo device is, and it never touches the network.
echo.
echo Safe to run as many times as you like. Each run absorbs any new evidence,
echo compares against your previous run, and rewrites the probe plan.
echo.
echo Action: !SAS_ACTION!
echo.

if /I "!SAS_ACTION!"=="Import" (
  powershell.exe -NoProfile -File "%~dp0scripts\Invoke-SasCybernetTopologySession.ps1" -Action Import -BundlePath "!SAS_BUNDLE!" -OpenResults
) else (
  powershell.exe -NoProfile -File "%~dp0scripts\Invoke-SasCybernetTopologySession.ps1" -Action !SAS_ACTION! -OpenResults
)
set "SAS_EXIT=!ERRORLEVEL!"

echo.
if "!SAS_EXIT!"=="0" (
  echo Topology survey iteration completed. The operator handoff was opened for you.
  echo.
  echo To feed the next run:
  echo   Your own probe results   -^> evidence\CybernetTopology\ingest
  echo   A colleague's bundle     -^> evidence\CybernetTopology\inbox
  echo   Your bundle to share out -^> evidence\CybernetTopology\outbox
  echo.
  echo Then just double-click this file again.
) else (
  echo Topology survey stopped with exit code !SAS_EXIT!.
  echo Nothing was probed and no device was reclassified.
  echo Keep the error shown above for your lead. Do not rerun blindly.
)
echo.
pause
endlocal & exit /b %SAS_EXIT%

:help
echo SysAdminSuite Cybernet Topology Survey
echo.
echo Double-click this file. No arguments needed, first time or any later time.
echo It creates the local session if missing, absorbs new evidence, recomputes
echo which CIDRs deserve a bounded targeted pass, and opens the operator handoff.
echo.
echo Optional command-line forms:
echo   Run-CybernetTopologySurvey.cmd
echo   Run-CybernetTopologySurvey.cmd Export
echo   Run-CybernetTopologySurvey.cmd Import "C:\path\to\colleague-bundle.json"
echo.
echo Evidence folders (all local and gitignored):
echo   evidence\CybernetTopology\ingest  - drop your own probe result JSON here
echo   evidence\CybernetTopology\inbox   - drop bundles received from other techs
echo   evidence\CybernetTopology\outbox  - bundles you can send to other techs
echo.
echo This planner performs no network activity and never decides whether a host
echo is a Cybernet. Hardware identity is a separate authority.
exit /b 0
