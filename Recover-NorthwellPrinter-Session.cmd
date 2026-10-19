@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Printer Session Recovery
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
rem Elevate before refreshing the trusted runtime so the same machine-local
rem state authority is used both before and after UAC.
"%SAS_PS%" -NoLogo -NoProfile -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {exit 0} else {exit 1}"
if not "%ERRORLEVEL%"=="0" (
  echo Administrator rights are required for protected target provisioning.
  set "SAS_SELF=%~f0"
  "%SAS_PS%" -NoLogo -NoProfile -Command "try { $p=Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('""{0}""' -f $env:SAS_SELF)) -Verb RunAs -Wait -PassThru; exit $p.ExitCode } catch { exit 1 }"
  set "SAS_ELEVATED_RC=!ERRORLEVEL!"
  if not "!SAS_ELEVATED_RC!"=="0" (
    echo ERROR: UAC was not approved or the elevated launcher failed.
    pause
  )
  exit /b !SAS_ELEVATED_RC!
)

rem Freshness is mandatory. A fallback launcher cannot run against stale
rem checkout/ZIP state or trust arbitrary files on PATH.
set "SAS_BOOTSTRAP=%~dp0Bootstrap-SysAdminSuitePrinter.ps1"
if not exist "%SAS_BOOTSTRAP%" (
  echo BLOCKED: trusted printer bootstrap is missing.
  pause
  exit /b 2
)
set "SAS_RECEIPT=%TEMP%\SasPrinterRuntime-%RANDOM%-%RANDOM%.txt"
"%SAS_PS%" -NoLogo -NoProfile -File "%SAS_BOOTSTRAP%" -NoLaunch -OutputRuntimePath "%SAS_RECEIPT%"
set "SAS_FRESH_RC=!ERRORLEVEL!"
if not "!SAS_FRESH_RC!"=="0" (
  if exist "%SAS_RECEIPT%" del /q "%SAS_RECEIPT%" >nul 2>&1
  echo BLOCKED: printer runtime freshness was not proven.
  pause
  exit /b 2
)
if not exist "%SAS_RECEIPT%" (
  echo BLOCKED: bootstrap did not produce an exact runtime receipt.
  pause
  exit /b 2
)
set "SAS_SELECTED_ROOT="
set /p "SAS_SELECTED_ROOT="<"%SAS_RECEIPT%"
del /q "%SAS_RECEIPT%" >nul 2>&1
if not defined SAS_SELECTED_ROOT (
  echo BLOCKED: exact current printer runtime path was blank.
  pause
  exit /b 2
)
set "SAS_STAGE=!SAS_SELECTED_ROOT!\mapping\SessionFallback\Stage-NorthwellPrinterSession.ps1"
set "SAS_POINTER=!SAS_SELECTED_ROOT!\mapping\Logs\LATEST-PATH.txt"
if not exist "!SAS_STAGE!" (
  echo BLOCKED: session fallback missing from selected refreshed printer runtime.
  pause
  exit /b 2
)

echo ===========================================================
echo  NORTHWELL PRINTER STANDARD-USER SESSION RECOVERY
echo ===========================================================
echo 1. Durable per-user logon task, recommended for future users
echo 2. One-shot Common Startup bridge, emergency only
echo 3. Inspect staged recovery for a workstation
echo 4. Retire owned recovery artifacts
echo 5. Persistent Startup, client-approved exception only
echo 6. Durable shareless logon task when C$ staging is denied
echo.
echo Existing SYSTEM machine registration MUST be proven first.
echo This workflow never changes printer drivers or domain policies.
echo ===========================================================
set "SAS_MODE="
set /p "SAS_MODE=Choose 1, 2, 3 or 4: "
set "SAS_ACTION="
if "%SAS_MODE%"=="1" set "SAS_ACTION=Task"
if "%SAS_MODE%"=="2" set "SAS_ACTION=OneShot"
if "%SAS_MODE%"=="3" set "SAS_ACTION=Status"
if "%SAS_MODE%"=="4" set "SAS_ACTION=Remove"
if "%SAS_MODE%"=="5" set "SAS_ACTION=Persistent"
if "%SAS_MODE%"=="6" set "SAS_ACTION=TaskShareless"
if not defined SAS_ACTION (
  echo No mode selected; no action taken.
  pause
  exit /b 3
)
set "SAS_HOST="
set /p "SAS_HOST=Approved workstation hostname (not an IP): "
if not defined SAS_HOST (
  echo No hostname given.
  pause
  exit /b 3
)
set "SAS_EVIDENCE="
if exist "%SAS_POINTER%" set /p "SAS_EVIDENCE="<"%SAS_POINTER%"
if "%SAS_MODE%"=="3" goto status
if "%SAS_MODE%"=="4" goto remove
set "SAS_EXTRA="
if "%SAS_MODE%"=="5" (
  echo LAST-RESORT MODE: a client-approved exception is mandatory.
  set "SAS_TICKET="
  set /p "SAS_TICKET=Client approval ticket ID: "
  "%SAS_PS%" -NoLogo -NoProfile -Command "if ($env:SAS_TICKET -cmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,79}$') {exit 0} else {exit 1}"
  if not "!ERRORLEVEL!"=="0" (
    echo BLOCKED: absent or invalid approval ID.
    pause
    exit /b 2
  )
  set "SAS_EXTRA=-ApprovalTicket !SAS_TICKET!"
)
if not defined SAS_EVIDENCE (
  echo BLOCKED: current canonical machine-wide evidence pointer missing.
  echo Map the workstation using the trusted current runtime first.
  pause
  exit /b 2
)
echo.
echo Read-only preflight for exact target and canonical evidence:
"%SAS_PS%" -NoLogo -NoProfile -File "%SAS_STAGE%" -Mode %SAS_ACTION% -ComputerName "!SAS_HOST!" -EvidenceRoot "!SAS_EVIDENCE!" !SAS_EXTRA! -Plan
if not "%ERRORLEVEL%"=="0" (
  echo BLOCKED: invalid M0 evidence or target. No fallback staged.
  pause
  exit /b 2
)
echo.
echo Only proceed after observing an approved STANDARD USER fail to
echo see the printer after a real sign-out and sign-in.
set "SAS_CONFIRM="
set /p "SAS_CONFIRM=Type APPLY to stage %SAS_ACTION% for %SAS_HOST%: "
if not "!SAS_CONFIRM!"=="APPLY" (
  echo CANCELLED. No fallback was staged.
  pause
  exit /b 3
)
"%SAS_PS%" -NoLogo -NoProfile -File "%SAS_STAGE%" -Mode %SAS_ACTION% -ComputerName "!SAS_HOST!" -EvidenceRoot "!SAS_EVIDENCE!" !SAS_EXTRA! -Apply
set "SAS_EXIT=!ERRORLEVEL!"
echo.
if "!SAS_EXIT!"=="0" (
  echo STAGED - NOT LIVE CERTIFIED. Log on as an approved standard user.
  echo Check HKCU connection and %%LOCALAPPDATA%%\SysAdminSuite\Printer receipt.
) else (
  echo RECOVERY NOT COMPLETE. Preserve error and inspect Status.
)
pause
exit /b !SAS_EXIT!

:status
"%SAS_PS%" -NoLogo -NoProfile -File "%SAS_STAGE%" -Mode Status -ComputerName "!SAS_HOST!"
set "SAS_EXIT=%ERRORLEVEL%"
pause
exit /b %SAS_EXIT%

:remove
set "SAS_CONFIRM="
set /p "SAS_CONFIRM=Type RETIRE to remove only owned fallback artifacts: "
if not "%SAS_CONFIRM%"=="RETIRE" exit /b 3
"%SAS_PS%" -NoLogo -NoProfile -File "%SAS_STAGE%" -Mode Remove -ComputerName "!SAS_HOST!" -Apply
set "SAS_EXIT=%ERRORLEVEL%"
pause
exit /b %SAS_EXIT%
