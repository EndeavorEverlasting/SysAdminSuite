@echo off
setlocal
cd /d "%~dp0"
echo [SAS] Running harness validation through Git Bash...
bash "%~dp0scripts/run-harness-validation.sh"
set "SAS_EXIT=%ERRORLEVEL%"
echo.
echo [SAS] Exit code: %SAS_EXIT%
pause
exit /b %SAS_EXIT%
