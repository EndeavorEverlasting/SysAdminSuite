@echo off
:: Launch-SysAdminSuite.bat
:: Double-click this file to open the SysAdminSuite GUI.
:: Requires PowerShell (5.1+) to be available on the system.

cd /d "%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0GUI\Start-SysAdminSuiteGui.ps1"

