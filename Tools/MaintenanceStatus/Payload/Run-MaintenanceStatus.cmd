@echo off
setlocal EnableExtensions

title SysAdminSuite - Maintenance Status Harness
mode con: cols=88 lines=30

REM ============================================================
REM SysAdminSuite Maintenance Status Launcher
REM Runs maintenance_status.sh without requiring local browsing.
REM Intended for UNC/file-share execution on restricted endpoints.
REM ============================================================

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%maintenance_status.sh"

REM Optional override:
REM Run-MaintenanceStatus.cmd "\\server\share\SysAdminSuite\Tools\MaintenanceStatus\Payload\maintenance_status.sh"
if not "%~1"=="" set "SCRIPT_PATH=%~1"

set "BASH_EXE="

if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%ProgramFiles%\Git\usr\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\usr\bin\bash.exe"
if not defined BASH_EXE if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%SystemRoot%\System32\bash.exe" set "BASH_EXE=%SystemRoot%\System32\bash.exe"

cls
echo ============================================================
echo              SysAdminSuite Maintenance Launcher
echo ============================================================
echo.
echo Script:
echo   %SCRIPT_PATH%
echo.

if not exist "%SCRIPT_PATH%" (
    echo ERROR:
    echo   maintenance_status.sh was not found.
    echo.
    echo Expected:
    echo   %SCRIPT_PATH%
    echo.
    echo Run this launcher from the same folder as maintenance_status.sh,
    echo or pass the full UNC path to the .sh file.
    echo.
    pause
    exit /b 2
)

if not defined BASH_EXE (
    echo ERROR:
    echo   Bash was not found on this workstation.
    echo.
    echo Checked:
    echo   %ProgramFiles%\Git\bin\bash.exe
    echo   %ProgramFiles%\Git\usr\bin\bash.exe
    echo   %ProgramFiles(x86)%\Git\bin\bash.exe
    echo   %SystemRoot%\System32\bash.exe
    echo.
    echo Fallback:
    echo   Use the CMD-only QR launcher version from the README.
    echo.
    pause
    exit /b 3
)

echo Bash:
echo   %BASH_EXE%
echo.
echo Starting maintenance status harness...
echo.

"%BASH_EXE%" "%SCRIPT_PATH%"

endlocal
