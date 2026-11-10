@echo off
setlocal
powershell.exe -Mta -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\SasBluetooth.ps1" %*
exit /b %errorlevel%
