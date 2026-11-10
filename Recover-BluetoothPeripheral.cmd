@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-BluetoothPeripheralRecovery.ps1" %*
exit /b %errorlevel%
