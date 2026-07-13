@echo off
rem Launcher for Invoke-BluetoothDriverFlush.ps1 targeted repair mode.
rem Usage: Run-BluetoothTargetRepair.cmd [TargetDeviceName]

set TARGET=%~1
if "%TARGET%"=="" (
    echo Usage: Run-BluetoothTargetRepair.cmd [TargetDeviceName]
    echo Example: Run-BluetoothTargetRepair.cmd "SineAudio DS6345"
    exit /b 1
)

echo Launching targeted Bluetooth repair for: %TARGET%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Utilities\Invoke-BluetoothDriverFlush.ps1" -TargetDeviceName "%TARGET%" -RemoveTarget
pause
