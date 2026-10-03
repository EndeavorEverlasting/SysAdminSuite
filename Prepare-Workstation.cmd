@echo off
cd /d "%~dp0"
set "ACTION=Plan"
if "%~1"=="" goto run
set "ACTION=%~1"
:run
pwsh.exe -NoLogo -NoProfile -File "%~dp0scripts\Invoke-SasWorkstationProvisioner.ps1" -Action %ACTION%
if errorlevel 1 (
    echo.
    echo Provisioner exited with errors. Review the output above.
    pause
)
