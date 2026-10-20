@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title SysAdminSuite - Printer Field Issue Report (Read Only)
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_INCIDENT=%~dp0scripts\Invoke-SasPrinterFieldIncident.ps1"
if not exist "%SAS_INCIDENT%" set "SAS_INCIDENT=%~dp0Invoke-SasPrinterFieldIncident.ps1"
if not exist "%SAS_INCIDENT%" (
  echo BLOCKED: printer incident collector is missing from this package.
  echo Use an approved SysAdminSuite field release or source checkout.
  pause
  exit /b 2
)
if not exist "%SAS_PS%" (
  echo BLOCKED: Windows PowerShell 5.1 is unavailable.
  pause
  exit /b 2
)
echo ================================================================
echo  SAS PRINTER FIELD INCIDENT - READ-ONLY LOCAL CAPTURE
echo ================================================================
echo 1. Machine-wide printer mapping failed
echo 2. Printer missing after standard user logged in
echo 3. Fallback deployment or staging failed
echo 4. Logon task did not map the printer
echo 5. Startup fallback or cleanup failed
echo 6. Download, launcher, or runtime integrity failed
echo 7. Other or uncertain printer issue
echo.
echo No administrator login, registry mutation, target probe or upload.
echo Workstation, account, print server and raw logs stay private.
echo ================================================================
set "SAS_CHOICE="
set /p "SAS_CHOICE=Choose issue 1-7: "
set "SAS_SYMPTOM="
if "%SAS_CHOICE%"=="1" set "SAS_SYMPTOM=mapping-failed"
if "%SAS_CHOICE%"=="2" set "SAS_SYMPTOM=standard-user-missing"
if "%SAS_CHOICE%"=="3" set "SAS_SYMPTOM=fallback-staging"
if "%SAS_CHOICE%"=="4" set "SAS_SYMPTOM=task-logon"
if "%SAS_CHOICE%"=="5" set "SAS_SYMPTOM=startup-cleanup"
if "%SAS_CHOICE%"=="6" set "SAS_SYMPTOM=launcher-download"
if "%SAS_CHOICE%"=="7" set "SAS_SYMPTOM=unknown"
if not defined SAS_SYMPTOM (
  echo CANCELLED: invalid issue choice. Nothing was changed.
  pause
  exit /b 3
)
"%SAS_PS%" -NoLogo -NoProfile -File "%SAS_INCIDENT%" -Symptom "%SAS_SYMPTOM%"
set "SAS_RC=%ERRORLEVEL%"
if not "%SAS_RC%"=="0" (
  echo FAILED: the local report could not be created. No remote action attempted.
  pause
  exit /b %SAS_RC%
)
set "SAS_LATEST=%LOCALAPPDATA%\SysAdminSuite\Evidence\PrinterSupport\latest-handoff.txt"
set "SAS_HANDOFF="
if exist "%SAS_LATEST%" set /p "SAS_HANDOFF="<"%SAS_LATEST%"
if defined SAS_HANDOFF if exist "%SAS_HANDOFF%" start "" notepad.exe "%SAS_HANDOFF%"
echo.
echo Hand the safe text to your agent. Keep full evidence private.
echo This report does NOT certify or fix any printer by itself.
echo The next agent should investigate, validate a repair, and track proof.
pause
exit /b 0
