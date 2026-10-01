@echo off
setlocal EnableExtensions
title SysAdminSuite - H&H CC Reader PAX Keypad Input Plan
cls

if not "%~1"=="" goto usage

if not exist "%~dp0scripts\ConvertTo-SasPaxKeypadPlan.ps1" (
  echo ERROR: keypad planning implementation is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER PAX KEYPAD INPUT PLAN
echo ================================================================
echo  Local deterministic guidance only. No reader contact.
echo  The text is entered interactively with hidden input and is not
echo  persisted in the evidence receipt.
echo.
echo  Known PAX-family path:
echo    number key containing the letter, then ALPHA until visible.
echo  Special-character mappings are never invented.
echo ================================================================
echo.

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\ConvertTo-SasPaxKeypadPlan.ps1" -Prompt
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Plan-HHCCReaderAlphaInput.cmd
echo.
echo The command prompts for the authorized text locally with hidden input.
exit /b 2
