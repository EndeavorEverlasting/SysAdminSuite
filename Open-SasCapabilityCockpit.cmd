@echo off
setlocal EnableExtensions
rem Admin Box operator front door: reuse the existing guarded dashboard launcher.
rem This command never contacts or changes an Android/PAX target.
if not exist "%~dp0START-HERE-SysAdminSuite-Dashboard.bat" (
  echo ERROR: Canonical SysAdminSuite dashboard launcher is missing.
  exit /b 2
)
call "%~dp0START-HERE-SysAdminSuite-Dashboard.bat" --capabilities
exit /b %ERRORLEVEL%
