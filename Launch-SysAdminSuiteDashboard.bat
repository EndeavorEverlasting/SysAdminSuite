@echo off
:: Launch-SysAdminSuiteDashboard.bat - double-click to open the web dashboard
:: Shows the Harold splash while server.py starts, then opens the browser.

start "" /B powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Launch-SysAdminSuiteDashboard.ps1"
exit
