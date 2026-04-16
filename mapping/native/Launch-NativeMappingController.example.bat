@echo off
setlocal
REM Example: run the native controller after building (see README.md).
REM Place SysAdminSuite.Mapping.Controller.exe and SysAdminSuite.Mapping.Worker.exe in the same folder.

set "BIN=%~dp0build\bin\Release"
if not exist "%BIN%\SysAdminSuite.Mapping.Controller.exe" set "BIN=%~dp0build\Release"

if not exist "%BIN%\SysAdminSuite.Mapping.Controller.exe" (
  echo Build the native tools first: mapping\native\README.md
  exit /b 1
)

REM Replace hosts with your list or use -ComputerFile path\to\hosts.txt
"%BIN%\SysAdminSuite.Mapping.Controller.exe" -Computer HOST1,HOST2 -WorkerArgs "-ListOnly -Preflight -OutputRoot C:\ProgramData\SysAdminSuite\Mapping"
exit /b %ERRORLEVEL%
