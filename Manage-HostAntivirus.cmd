@echo off
setlocal
if "%~1"=="" (
    py -3 -I "%~dp0scripts\sas_antivirus.py" inspect
) else (
    py -3 -I "%~dp0scripts\sas_antivirus.py" %*
)
exit /b %ERRORLEVEL%
