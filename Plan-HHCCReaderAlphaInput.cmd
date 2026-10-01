@echo off
setlocal EnableExtensions
title SysAdminSuite - H&H CC Reader PAX Keypad Input Plan
cls

if "%~1"=="" goto usage
if not "%~2"=="" goto usage

if not exist "%~dp0scripts\ConvertTo-SasPaxKeypadPlan.ps1" (
  echo ERROR: keypad planning implementation is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER PAX KEYPAD INPUT PLAN
echo ================================================================
echo  Local deterministic guidance only. No reader contact.
echo  This helper does not store the supplied text in repository files.
echo.
echo  It uses documented PAX-family keypad behavior:
echo    number key first, then ALPHA until the requested letter appears.
echo  Special-character mappings are never invented.
echo ================================================================
echo.

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\ConvertTo-SasPaxKeypadPlan.ps1" -Text "%~1"
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Plan-HHCCReaderAlphaInput.cmd "TEXT"
echo.
echo Use only with an authorized credential or harmless dry-run text.
echo The helper plans key entry; it does not validate a password.
exit /b 2
