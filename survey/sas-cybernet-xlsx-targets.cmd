@echo off
setlocal EnableExtensions
set "REPO=%~dp0.."
call "%~dp0sas-windows-runtime.cmd" || exit /b 1
"%SAS_BASH_EXE%" "%REPO%\survey\sas-cybernet-xlsx-targets.sh" %*
exit /b %ERRORLEVEL%
