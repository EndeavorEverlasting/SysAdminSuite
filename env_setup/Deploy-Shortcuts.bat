@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ------------------------------------------------------------------------------
rem Config (defaults) - can be overridden via CLI switches
rem ------------------------------------------------------------------------------
set "SOURCEDIR=\\LPW003ASI037\C$\Shortcuts"
set "PREFIX=WLS111WCC"
set "START=1"
set "END=164"
set "LIST="
set "WHATIF="

rem ------------------------------------------------------------------------------
rem Parse arguments (/SOURCEDIR=, /PREFIX=, /START=, /END=, /LIST=, /WHATIF)
rem ------------------------------------------------------------------------------
for %%A in (%*) do (
  set "ARG=%%~A"
  set "KV=!ARG:~1!"  rem strip leading slash
  for /f "tokens=1,2 delims==" %%K in ("!KV!") do (
    set "K=%%~K"
    set "V=%%~L"
  )
  if /I "!K!"=="SOURCEDIR" set "SOURCEDIR=!V!"
  if /I "!K!"=="PREFIX"    set "PREFIX=!V!"
  if /I "!K!"=="START"     set "START=!V!"
  if /I "!K!"=="END"       set "END=!V!"
  if /I "!K!"=="LIST"      set "LIST=!V!"
  if /I "!K!"=="WHATIF"    set "WHATIF=1"
)

rem ------------------------------------------------------------------------------
rem Timestamp (US locale dependent; pads hour if needed)
rem ------------------------------------------------------------------------------
set "TS=%date:~10,4%%date:~4,2%%date:~7,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "TS=%TS: =0%"

rem ------------------------------------------------------------------------------
rem Logs
rem ------------------------------------------------------------------------------
set "LOGROOT=%SystemDrive%\ShortcutDeployLogs"
if not exist "%LOGROOT%" md "%LOGROOT%" >nul 2>&1
set "LOGTXT=%LOGROOT%\DeployShortcuts_%TS%.txt"
set "LOGCSV=%LOGROOT%\DeployShortcuts_%TS%.csv"

call :LogLine "Deployment started as %USERNAME% from %COMPUTERNAME% | CMD"
call :LogLine "SourceDir: %SOURCEDIR%"

> "%LOGCSV%" echo Time,Hostname,File,Status,Detail

rem ------------------------------------------------------------------------------
rem Discover source files (first match for each label and extension)
rem ------------------------------------------------------------------------------
set "SRC1=" & set "SRC1NAME="
set "SRC2=" & set "SRC2NAME="

call :FindSource "%SOURCEDIR%" "Nuance Powershare*.lnk" "Nuance Powershare*.url" "Nuance Powershare*.website"
set "SRC1=!RET!" & set "SRC1NAME=!RETNAME!"

call :FindSource "%SOURCEDIR%" "Welcome to Cerner*.lnk" "Welcome to Cerner*.url" "Welcome to Cerner*.website"
set "SRC2=!RET!" & set "SRC2NAME=!RETNAME!"

if defined SRC1 (
  for %%Z in ("!SRC1!") do (
    for %%S in (%%~z) do set "SRC1SIZE=%%~z"
  )
  call :LogLine "FOUND source for 'Nuance Powershare': !SRC1NAME!"
) else (
  call :LogLine "MISSING source for 'Nuance Powershare' in %SOURCEDIR% - will SKIP."
  call :CsvLog "" "Nuance Powershare" "MISSING_SOURCE" "No matching files in %SOURCEDIR%"
)

if defined SRC2 (
  for %%Z in ("!SRC2!") do (
    for %%S in (%%~z) do set "SRC2SIZE=%%~z"
  )
  call :LogLine "FOUND source for 'Welcome to Cerner': !SRC2NAME!"
) else (
  call :LogLine "MISSING source for 'Welcome to Cerner' in %SOURCEDIR% - will SKIP."
  call :CsvLog "" "Welcome to Cerner" "MISSING_SOURCE" "No matching files in %SOURCEDIR%"
)

if not defined SRC1 if not defined SRC2 (
  call :LogLine "No source files discovered. Aborting."
  goto :Tail
)

rem ------------------------------------------------------------------------------
rem Build target list and process
rem ------------------------------------------------------------------------------
if defined LIST (
  for %%H in (%LIST%) do call :ProcessHost "%%~H"
) else (
  for /L %%N in (%START%,1,%END%) do (
    set "NUM=00%%N"
    set "NUM=!NUM:~-3!"
    set "H=!PREFIX!!NUM!"
    call :ProcessHost "!H!"
  )
)

goto :Tail

rem ==============================================================================
rem Subroutines
rem ==============================================================================

:ProcessHost
setlocal
set "HOST=%~1"
set "DEST=\\%HOST%\C$\Users\Public\Desktop"
call :LogLine "Checking %HOST%..."

rem Check directory exists / accessible. Use DIR to capture message.
if exist "%DEST%\nul" (
  rem ok
) else (
  dir "%DEST%" >"%TEMP%\__chk_%HOST%.txt" 2>&1
  findstr /I /C:"Access is denied" "%TEMP%\__chk_%HOST%.txt" >nul && (
    call :LogLine "ACCESS DENIED to %DEST%"
    call :CsvLog "%HOST%" "" "ACCESS_DENIED" "Access is denied"
    del "%TEMP%\__chk_%HOST%.txt" >nul 2>&1
    endlocal & goto :eof
  )
  findstr /I /C:"network path was not found" "%TEMP%\__chk_%HOST%.txt" >nul && (
    call :LogLine "SMB port/share not reachable on %HOST%."
    call :CsvLog "%HOST%" "" "SMB_UNREACHABLE" "Network path was not found"
    del "%TEMP%\__chk_%HOST%.txt" >nul 2>&1
    endlocal & goto :eof
  )
  findstr /I /C:"network name cannot be found" "%TEMP%\__chk_%HOST%.txt" >nul && (
    call :LogLine "SMB port/share not reachable on %HOST%."
    call :CsvLog "%HOST%" "" "SMB_UNREACHABLE" "Network name cannot be found"
    del "%TEMP%\__chk_%HOST%.txt" >nul 2>&1
    endlocal & goto :eof
  )
  findstr /I /C:"The system cannot find the path specified" "%TEMP%\__chk_%HOST%.txt" >nul && (
    call :LogLine "DEST PATH NOT FOUND: %DEST%"
    call :CsvLog "%HOST%" "" "DEST_NOT_FOUND" "Path not found"
    del "%TEMP%\__chk_%HOST%.txt" >nul 2>&1
    endlocal & goto :eof
  )
  rem Fallback: treat as unreachable
  call :LogLine "SMB port/share not reachable on %HOST%."
  call :CsvLog "%HOST%" "" "SMB_UNREACHABLE" "Unknown SMB error"
  del "%TEMP%\__chk_%HOST%.txt" >nul 2>&1
  endlocal & goto :eof
)

if defined SRC1 call :CopyOne "%HOST%" "%SOURCEDIR%" "%DEST%" "%SRC1NAME%"
if defined SRC2 call :CopyOne "%HOST%" "%SOURCEDIR%" "%DEST%" "%SRC2NAME%"

endlocal
goto :eof

:CopyOne
setlocal
set "HOST=%~1"
set "SRC_DIR=%~2"
set "DST_DIR=%~3"
set "FNAME=%~4"

if defined WHATIF (
  call :LogLine "WHATIF: Would copy %FNAME% to %HOST%"
  call :CsvLog "%HOST%" "%FNAME%" "WHATIF" "%DST_DIR%\%FNAME%"
  endlocal & goto :eof
)

rem Use ROBOCOPY for robust UNC copies; interpret return code.
robocopy "%SRC_DIR%" "%DST_DIR%" "%FNAME%" /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
  call :LogLine "UP-TO-DATE on %HOST% : %FNAME%"
  call :CsvLog "%HOST%" "%FNAME%" "UPTODATE" "%DST_DIR%\%FNAME%"
) else if %RC% LSS 8 (
  rem 1..7 are successes/warnings for our use-case
  call :LogLine "SUCCESS: Copied %FNAME% to %HOST%"
  call :CsvLog "%HOST%" "%FNAME%" "SUCCESS" "%DST_DIR%\%FNAME%"
) else (
  call :LogLine "ERROR: Failed to copy %FNAME% to %HOST% (robocopy rc=%RC%)"
  call :CsvLog "%HOST%" "%FNAME%" "ERROR" "robocopy rc=%RC%"
)

endlocal
goto :eof

:FindSource
rem Args: 1=dir  2..n=patterns. Returns RET (full path) and RETNAME (file) if found.
setlocal
set "RET="
set "RETNAME="
set "SRCDIR=%~1"
shift
:FS_LOOP
if "%~1"=="" goto FS_DONE
for /f "delims=" %%F in ('dir /b /a:-d "%SRCDIR%\%~1" 2^>nul') do (
  set "RET=%SRCDIR%\%%~F"
  set "RETNAME=%%~F"
  goto FS_DONE
)
shift
goto FS_LOOP
:FS_DONE
endlocal & set "RET=%RET%" & set "RETNAME=%RETNAME%"
goto :eof

:Stamp
set "STAMP=[%date% %time%]"
goto :eof

:LogLine
call :Stamp
>> "%LOGTXT%" echo %STAMP% %~1
echo %STAMP% %~1
goto :eof

:CsvLog
rem Args: host, file, status, detail
for /f "tokens=1-3 delims=:" %%h in ("%time%") do set "_h=%%h" & set "_m=%%i" & set "_s=%%j"
set "_now=%date% %_h%:%_m%:%_s%"
set "_detail=%~4"
set "_detail=%_detail:""="%"
>> "%LOGCSV%" echo %_now%,%~1,"%~2",%~3,"%_detail%"
goto :eof

:Tail
echo.
echo Logs:
echo   Text:       %LOGTXT%
echo   CSV:        %LOGCSV%
endlocal
