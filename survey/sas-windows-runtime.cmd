@echo off
rem Shared Windows runtime bootstrap for SysAdminSuite survey launchers.
rem Intentionally does not use SETLOCAL so variables and PATH return to the caller.

set "SAS_BASH_EXE="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "SAS_BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not defined SAS_BASH_EXE if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "SAS_BASH_EXE=%LocalAppData%\Programs\Git\bin\bash.exe"
if not defined SAS_BASH_EXE for /f "delims=" %%B in ('where bash 2^>nul') do if not defined SAS_BASH_EXE set "SAS_BASH_EXE=%%B"
if not defined SAS_BASH_EXE (
  echo [SysAdminSuite] ERROR: Git Bash was not found. Install Git for Windows or add Git Bash to PATH.
  exit /b 1
)

set "SAS_PYTHON_LAUNCHER="
py -3 -c "import sys" >nul 2>&1 && set "SAS_PYTHON_LAUNCHER=py -3"
if not defined SAS_PYTHON_LAUNCHER python -c "import sys" >nul 2>&1 && set "SAS_PYTHON_LAUNCHER=python"
if not defined SAS_PYTHON_LAUNCHER python3 -c "import sys" >nul 2>&1 && set "SAS_PYTHON_LAUNCHER=python3"
if not defined SAS_PYTHON_LAUNCHER (
  echo [SysAdminSuite] ERROR: A working Python 3 runtime was not found.
  echo Verify that ^"py -3 --version^" or ^"python --version^" works in Command Prompt.
  exit /b 1
)

set "SAS_PYTHON_SHIM=%TEMP%\SysAdminSuite-python-shim"
if not exist "%SAS_PYTHON_SHIM%" mkdir "%SAS_PYTHON_SHIM%" >nul 2>&1
>"%SAS_PYTHON_SHIM%\python3.cmd" echo @echo off
>>"%SAS_PYTHON_SHIM%\python3.cmd" echo %SAS_PYTHON_LAUNCHER% %%*
>"%SAS_PYTHON_SHIM%\python.cmd" echo @echo off
>>"%SAS_PYTHON_SHIM%\python.cmd" echo %SAS_PYTHON_LAUNCHER% %%*
>"%SAS_PYTHON_SHIM%\python3" echo #!/usr/bin/env bash
>>"%SAS_PYTHON_SHIM%\python3" echo exec %SAS_PYTHON_LAUNCHER% "$@"
>"%SAS_PYTHON_SHIM%\python" echo #!/usr/bin/env bash
>>"%SAS_PYTHON_SHIM%\python" echo exec %SAS_PYTHON_LAUNCHER% "$@"
set "PATH=%SAS_PYTHON_SHIM%;%PATH%"

exit /b 0
