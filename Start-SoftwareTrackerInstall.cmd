@echo off
setlocal

set "ROOT=%~dp0"
set "BASH=%ProgramFiles%\Git\bin\bash.exe"

if not exist "%BASH%" (
  echo Git Bash was not found at:
  echo   %BASH%
  echo.
  echo Install Git for Windows or run:
  echo   bash scripts/sas-software-tracker-install.sh --tracker ^<Software Tracker.xlsx^>
  exit /b 2
)

echo SysAdminSuite Software Tracker install automation
echo.
echo Dry-run is the default. Real installs require --execute.
echo Real Software Tracker.xlsx files stay local and ignored by git.
echo.
"%BASH%" -lc "cd '%ROOT:\=/%' && bash scripts/sas-software-tracker-install.sh --help"

endlocal
