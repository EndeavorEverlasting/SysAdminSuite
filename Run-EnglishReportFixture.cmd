@echo off
setlocal
cd /d "%~dp0"
echo [SAS] Rendering English report fixtures through Git Bash...
bash "%~dp0scripts/render-english-report-fixtures.sh"
set "SAS_EXIT=%ERRORLEVEL%"
echo.
echo [SAS] Exit code: %SAS_EXIT%
echo [SAS] Output path: survey\output\english-log\
pause
exit /b %SAS_EXIT%
