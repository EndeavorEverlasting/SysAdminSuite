@echo off
setlocal
cd /d "%~dp0"
echo [SAS] Showing harness evidence paths through Git Bash...
bash "%~dp0scripts/show-harness-evidence-paths.sh"
set "SAS_EXIT=%ERRORLEVEL%"
echo.
echo [SAS] Exit code: %SAS_EXIT%
pause
exit /b %SAS_EXIT%
