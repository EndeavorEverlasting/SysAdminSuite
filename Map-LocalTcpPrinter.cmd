@echo off
setlocal
title SysAdminSuite - Local TCP Printer Mapping
set "SAS_LOCAL_PRINTER_GUI=%~dp0GUI\Start-LocalTcpPrinterGui.ps1"
if not exist "%SAS_LOCAL_PRINTER_GUI%" (
  echo ERROR: SysAdminSuite local printer GUI is missing from this installation.
  pause
  exit /b 2
)
rem Local TCP port and queue registration may require administrator privileges.
rem Prompt for UAC once, before the native app opens; do not require a command shell.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:SAS_LOCAL_PRINTER_GUI; Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -Wait -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File ' + [char]34 + $p + [char]34)"
if errorlevel 1 (
  echo Printer mapping app was not started or elevated. No mapping has been requested.
  pause
  exit /b 1
)
exit /b 0
