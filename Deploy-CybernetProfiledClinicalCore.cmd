@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
if "%~1"=="" goto help

echo NETWORK REQUIRED: PROTECTED NORTHWELL
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1" -ComputerName "%~1" -EquipmentProfile Cybernet -AllowTargetMutation -ConfirmDeployment
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Profiled clinical-core transaction finished with exit code %EXITCODE%. Use sas context or sas next; do not reconstruct the run manually.
for %%# in (%EXITCODE%) do endlocal ^& exit /b %%#

:help
echo Usage: Deploy-CybernetProfiledClinicalCore.cmd CYBERNET-HOST
echo The tracked Cybernet launcher is the explicit equipment-profile authority for this lane; the target is then locked canonically.
echo One transaction owns: protected-network gate, exact prior-run recovery, all-five source preflight, harmless transport readiness,
echo staging/hash verification, SYSTEM execution, before/after Cybernet profile capture, final evidence, and exact cleanup.
echo AutoLogon is observed/preserved only. Imprivata is observational/external. No reboot is performed.
exit /b 2