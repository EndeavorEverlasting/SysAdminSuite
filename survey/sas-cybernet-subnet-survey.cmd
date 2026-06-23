@echo off
setlocal EnableExtensions
set "REPO=%~dp0.."
where bash >nul 2>&1 || (
  echo Git Bash bash.exe not on PATH.
  exit /b 1
)
bash "%REPO%\survey\sas-cybernet-subnet-survey.sh" %*
exit /b %ERRORLEVEL%
