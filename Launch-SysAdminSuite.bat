@echo off
:: Launch-SysAdminSuite.bat — double-click to open the GUI
:: Starts PowerShell in STA mode with execution policy bypass

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0GUI\Start-SysAdminSuiteGui.ps1"

