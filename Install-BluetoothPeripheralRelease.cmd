@echo off
setlocal
rem Run from an approved prepared bundle. No network fetch or automatic activation.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-BluetoothPeripheralRelease.ps1" %*
exit /b %errorlevel%
