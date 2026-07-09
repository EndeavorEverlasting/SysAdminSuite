@echo off
setlocal
cd /d "%~dp0"

where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    set "SAS_PS=pwsh"
) else (
    set "SAS_PS=powershell.exe"
)

if not exist "%~dp0survey\output\english-log" mkdir "%~dp0survey\output\english-log"

echo [SAS] Rendering serial preflight fixture report through PowerShell...
"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Render-SasEnglishReport.ps1" -SummaryJson "%~dp0survey\fixtures\english-log\serial_preflight_summary.sample.json" -ArtifactRegistry "%~dp0survey\fixtures\english-log\serial_preflight_artifact_registry.sample.json" -Template serial-preflight -OutputPath "%~dp0survey\output\english-log\serial_preflight_report.md"
if %ERRORLEVEL% NEQ 0 goto :fail

echo [SAS] Rendering network preflight fixture report through PowerShell...
"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Render-SasEnglishReport.ps1" -SummaryJson "%~dp0survey\fixtures\english-log\network_preflight_summary.sample.json" -ArtifactRegistry "%~dp0survey\fixtures\english-log\network_preflight_artifact_registry.sample.json" -Template network-preflight -OutputPath "%~dp0survey\output\english-log\network_preflight_report.md"
if %ERRORLEVEL% NEQ 0 goto :fail

set "SAS_EXIT=0"
goto :done

:fail
set "SAS_EXIT=%ERRORLEVEL%"

:done
echo.
echo [SAS] Exit code: %SAS_EXIT%
echo [SAS] Output path: survey\output\english-log\
pause
exit /b %SAS_EXIT%
