@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
echo SysAdminSuite - Cybernet COM Port AutoFix
echo Mode: DRY RUN ONLY
echo Evidence: C:\Temp\CybernetCOM\autofix_*
echo This captures evidence and previews the mapping. It does not apply changes or restart.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-CybernetComPortAutoFix.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Cybernet COM Port AutoFix dry run failed. Check the console output and evidence folder.
endlocal & exit /b %EXITCODE%
