@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "SAS_COM_AUTOFIX_ARGS=%*"
echo SysAdminSuite - Cybernet COM Port AutoFix
echo Mode: DRY RUN ONLY
echo Evidence: C:\Temp\CybernetCOM\autofix_*
echo This captures evidence and previews the mapping. It does not apply changes or restart.
echo.
if defined SAS_COM_AUTOFIX_ARGS (
  echo ERROR: The dry-run launcher does not accept arguments. Run it without -Apply, -Restart, or -Force.
  exit /b 2
)
powershell.exe -NoProfile -File "%SCRIPT_DIR%scripts\Start-CybernetComPortAutoFix.ps1" -Mode DryRun
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Cybernet COM Port AutoFix dry run failed. Check the console output and evidence folder.
endlocal & exit /b %EXITCODE%
