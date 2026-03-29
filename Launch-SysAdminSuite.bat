@echo off
:: Launch-SysAdminSuite.bat — double-click to open the GUI
:: Uses START /B so the CMD window closes immediately, preventing
:: Ctrl+C from sending PipelineStoppedException into the WinForms GUI.

start "" /B powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0GUI\Start-SysAdminSuiteGui.ps1"
exit
