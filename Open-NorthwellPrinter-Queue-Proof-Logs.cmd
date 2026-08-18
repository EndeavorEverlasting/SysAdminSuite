@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "SAS_EVIDENCE=%LOCALAPPDATA%\SysAdminSuite\field-runs\printer-queue-proof"
set "SAS_SUMMARY=%SAS_EVIDENCE%\latest.txt"
set "SAS_JSON=%SAS_EVIDENCE%\latest.json"
set "SAS_POINTER=%SAS_EVIDENCE%\LATEST-PATH.txt"

if not exist "%SAS_EVIDENCE%" (
    echo No printer queue evidence directory exists yet:
    echo %SAS_EVIDENCE%
    pause
    exit /b 2
)

start "SysAdminSuite printer evidence" explorer.exe "%SAS_EVIDENCE%"
if exist "%SAS_SUMMARY%" start "Printer latest summary" notepad.exe "%SAS_SUMMARY%"
if exist "%SAS_JSON%" start "Printer latest JSON" notepad.exe "%SAS_JSON%"
if exist "%SAS_POINTER%" start "Printer latest paths" notepad.exe "%SAS_POINTER%"

exit /b 0
