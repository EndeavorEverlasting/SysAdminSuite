@echo off
setlocal EnableExtensions

REM ============================================================
REM Register Maintenance Status Harness at user logon
REM Intended for restricted endpoints where local browsing is blocked.
REM ============================================================

set "TASK_NAME=SysAdminSuite Maintenance Status"
set "LAUNCHER=%~dp0Run-MaintenanceStatus.cmd"

REM Optional override:
REM Register-MaintenanceStatus-Task.cmd "\\server\share\SysAdminSuite\Tools\MaintenanceStatus\Payload\Run-MaintenanceStatus.cmd"
if not "%~1"=="" set "LAUNCHER=%~1"

cls
echo ============================================================
echo        Register SysAdminSuite Maintenance Status Task
echo ============================================================
echo.
echo Task:
echo   %TASK_NAME%
echo.
echo Launcher:
echo   %LAUNCHER%
echo.

if not exist "%LAUNCHER%" (
    echo ERROR:
    echo   Launcher not found.
    echo.
    echo Use a full UNC path if running from a restricted workstation.
    echo.
    pause
    exit /b 2
)

schtasks /Create ^
 /TN "%TASK_NAME%" ^
 /SC ONLOGON ^
 /TR "\"%LAUNCHER%\"" ^
 /F

if errorlevel 1 (
    echo.
    echo ERROR:
    echo   Task registration failed.
    echo.
    echo Possible causes:
    echo   - Task Scheduler blocked by policy
    echo   - Permission issue
    echo   - UNC path inaccessible at logon
    echo.
    pause
    exit /b 3
)

echo.
echo Registered successfully.
echo.
echo To test now:
echo   schtasks /Run /TN "%TASK_NAME%"
echo.
pause
endlocal
