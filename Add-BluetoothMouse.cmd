@echo off
setlocal
powershell.exe -Mta -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Add-BluetoothMouse.ps1" %*
exit /b %errorlevel%
