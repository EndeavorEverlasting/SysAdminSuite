@echo off
setlocal
call "%~dp0Run-InstallApprovedSoftware.cmd" %*
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
