@echo off
setlocal
cd /d "%~dp0"

echo [SAS] Harness output locations
echo.
echo Validator output:
echo   survey\output\harness-validator\
echo.
echo English reports:
echo   survey\output\english-log\
echo.
echo Run contexts:
echo   survey\output\runs\
echo.
echo Latest reviewed evidence pointer:
echo   docs\evidence\latest\README.md
echo.
echo Keep generated run output local unless it is reviewed and intentionally sanitized.
set "SAS_EXIT=0"
echo.
echo [SAS] Exit code: %SAS_EXIT%
pause
exit /b %SAS_EXIT%
