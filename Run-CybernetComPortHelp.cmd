@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - Cybernet COM Port Help
powershell.exe -NoProfile -File "%SCRIPT_DIR%scripts\Show-CybernetComPortHelp.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Cybernet COM Port Help finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
