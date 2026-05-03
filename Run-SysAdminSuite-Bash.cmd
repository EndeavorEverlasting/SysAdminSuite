@echo off
setlocal EnableExtensions

rem SysAdminSuite Bash launcher for Windows CMD.
rem Finds Git Bash when bash.exe is not on PATH, then dispatches to bash/sysadminsuite.sh.

set "SCRIPT_DIR=%~dp0"
set "RUNNER=%SCRIPT_DIR%bash\sysadminsuite.sh"

if not exist "%RUNNER%" (
    echo [ERROR] Bash runner not found: %RUNNER%
    exit /b 1
)

set "BASH_EXE="

where bash.exe >nul 2>nul
if %ERRORLEVEL%==0 (
    for /f "delims=" %%I in ('where bash.exe 2^>nul') do (
        if not defined BASH_EXE set "BASH_EXE=%%I"
    )
)

if not defined BASH_EXE if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%ProgramFiles%\Git\usr\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\usr\bin\bash.exe"
if not defined BASH_EXE if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "BASH_EXE=%LocalAppData%\Programs\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%LocalAppData%\Programs\Git\usr\bin\bash.exe" set "BASH_EXE=%LocalAppData%\Programs\Git\usr\bin\bash.exe"

if not defined BASH_EXE (
    echo [ERROR] bash.exe was not found.
    echo.
    echo Install Git for Windows with Git Bash, or add Git Bash to PATH.
    echo Common path: C:\Program Files\Git\bin\bash.exe
    exit /b 9009
)

"%BASH_EXE%" "%RUNNER%" %*
exit /b %ERRORLEVEL%
