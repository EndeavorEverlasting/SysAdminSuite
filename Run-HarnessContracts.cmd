@echo off
setlocal
cd /d "%~dp0"
echo [SAS] Running harness contract suite through Git Bash...
bash "%~dp0Tests/bash/run_harness_contracts.sh"
set "SAS_EXIT=%ERRORLEVEL%"
echo.
echo [SAS] Exit code: %SAS_EXIT%
pause
exit /b %SAS_EXIT%
