@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM SysAdminSuite Maintenance Status Fleet Controller
REM Admin-box controller. Reads targets, probes reachability, writes
REM local HTML/CSV output, and stages target payload only when asked.
REM
REM Hub assumption:
REM   Akbarnator / WMH300OPR378 is the expected staging hub. Targets are
REM   NOT assumed to have SysAdminSuite installed.
REM ============================================================

set "CONTROLLER_DIR=%~dp0"
for %%I in ("%CONTROLLER_DIR%..") do set "ROOT_DIR=%%~fI"
set "PAYLOAD_DIR=%ROOT_DIR%\Payload"
set "OUTPUT_DIR=%ROOT_DIR%\Output"
set "TARGET_FILE=%~1"
set "STAMP=%DATE:/=-%_%TIME::=-%"
set "STAMP=%STAMP: =0%"
set "REPORT_HTML=%OUTPUT_DIR%\MaintenanceStatus_Report_%COMPUTERNAME%_%STAMP%.html"
set "REPORT_CSV=%OUTPUT_DIR%\MaintenanceStatus_Report_%COMPUTERNAME%_%STAMP%.csv"
set "AKBARNATOR_HOST=WMH300OPR378"
set "SUPPORT_REL=SUPPORT"
set "FALLBACK_ADMIN_SHARE=C$"
set "REMOTE_STAGE_REL=SUPPORT\SysAdminSuite\MaintenanceStatus"
set "REMOTE_LAUNCHER=C:\SUPPORT\SysAdminSuite\MaintenanceStatus\Run-MaintenanceStatus.cmd"

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%" >nul 2>nul

cls
echo ============================================================
echo          SysAdminSuite Maintenance Status Fleet
echo ============================================================
echo.
echo Admin Box : %COMPUTERNAME%
echo Hub       : %AKBARNATOR_HOST% / Akbarnator
echo Controller: %CONTROLLER_DIR%
echo Payload   : %PAYLOAD_DIR%
echo Output    : %OUTPUT_DIR%
echo.

if "%TARGET_FILE%"=="" goto :NoTargetFile
if not exist "%TARGET_FILE%" goto :MissingTargetFile
goto :ProcessTargets

:NoTargetFile
echo No target file supplied.
echo.
choice /C YN /M "Run local report for current workstation %COMPUTERNAME%"
if errorlevel 2 exit /b 0
set "TARGET_FILE=%OUTPUT_DIR%\_local_target_%COMPUTERNAME%_%STAMP%.csv"
> "%TARGET_FILE%" echo Hostname,Mode,Action,Notes
>> "%TARGET_FILE%" echo %COMPUTERNAME%,LocalConfirm,ProbeOnly,Generated because no target file was supplied
goto :ProcessTargets

:MissingTargetFile
echo ERROR:
echo   Target file not found:
echo   %TARGET_FILE%
echo.
echo Use a CSV/TXT file path, or run with no argument for current workstation confirmation.
exit /b 2

:ProcessTargets
call :WriteReportHeader
> "%REPORT_CSV%" echo Hostname,Mode,Action,PingStatus,ShareStatus,SharePath,PayloadStatus,TaskStatus,Notes

echo Target file:
echo   %TARGET_FILE%
echo.
echo Processing targets...
echo.

for /f "usebackq skip=1 tokens=1-4 delims=," %%A in ("%TARGET_FILE%") do (
    set "HOST=%%~A"
    set "MODE=%%~B"
    set "ACTION=%%~C"
    set "NOTES=%%~D"

    if not "!HOST!"=="" call :ProcessOne "!HOST!" "!MODE!" "!ACTION!" "!NOTES!"
)

call :WriteReportFooter

echo.
echo Complete.
echo HTML report:
echo   %REPORT_HTML%
echo CSV report:
echo   %REPORT_CSV%
echo.
start "" "%REPORT_HTML%" >nul 2>nul
exit /b 0

:ProcessOne
set "HOST=%~1"
set "MODE=%~2"
set "ACTION=%~3"
set "NOTES=%~4"
set "PING_STATUS=Fail"
set "SHARE_STATUS=NotChecked"
set "SHARE_PATH="
set "PAYLOAD_STATUS=NotRequested"
set "TASK_STATUS=NotRequested"

echo ------------------------------------------------------------
echo Target: %HOST%
echo Mode  : %MODE%
echo Action: %ACTION%

ping -n 1 -w 1000 "%HOST%" >nul 2>nul
if not errorlevel 1 set "PING_STATUS=Pass"

if /I "%MODE%"=="LocalConfirm" (
    set "SHARE_STATUS=Local"
    set "SHARE_PATH=%COMPUTERNAME%"
) else (
    call :ResolveTargetShare "%HOST%"
)

if /I "%ACTION%"=="StageOnly" call :StagePayload "%HOST%"
if /I "%ACTION%"=="StageAndRegister" call :StagePayload "%HOST%"
if /I "%ACTION%"=="StageAndRegister" call :RegisterRemoteTask "%HOST%"

echo Ping      : %PING_STATUS%
echo Share     : %SHARE_STATUS%
echo Share Path: %SHARE_PATH%
echo Payload   : %PAYLOAD_STATUS%
echo Task      : %TASK_STATUS%

>> "%REPORT_CSV%" echo %HOST%,%MODE%,%ACTION%,%PING_STATUS%,%SHARE_STATUS%,%SHARE_PATH%,%PAYLOAD_STATUS%,%TASK_STATUS%,%NOTES%
call :WriteReportRow "%HOST%" "%MODE%" "%ACTION%" "%PING_STATUS%" "%SHARE_STATUS%" "%SHARE_PATH%" "%PAYLOAD_STATUS%" "%TASK_STATUS%" "%NOTES%"
exit /b 0

:ResolveTargetShare
set "HOST=%~1"
set "PRIMARY=\\%HOST%\C$\%SUPPORT_REL%"
set "FALLBACK=\\%HOST%\%FALLBACK_ADMIN_SHARE%"
set "SHARE_STATUS=Fail"
set "SHARE_PATH="

if exist "%PRIMARY%\" (
    set "SHARE_STATUS=C$SupportPath"
    set "SHARE_PATH=%PRIMARY%"
    exit /b 0
)

if exist "%FALLBACK%\" (
    set "SHARE_STATUS=AdminShareFallback"
    set "SHARE_PATH=%FALLBACK%"
    exit /b 0
)

set "SHARE_STATUS=NoShare"
exit /b 0

:StagePayload
set "HOST=%~1"

if /I "%HOST%"=="%COMPUTERNAME%" (
    set "PAYLOAD_STATUS=SkippedLocal"
    exit /b 0
)

if "%SHARE_STATUS%"=="NoShare" (
    set "PAYLOAD_STATUS=NoShare"
    exit /b 0
)

if "%SHARE_PATH%"=="" (
    set "PAYLOAD_STATUS=NoSharePath"
    exit /b 0
)

if /I "%SHARE_STATUS%"=="C$SupportPath" (
    set "REMOTE_DIR=%SHARE_PATH%\SysAdminSuite\MaintenanceStatus"
) else (
    set "REMOTE_DIR=%SHARE_PATH%\SUPPORT\SysAdminSuite\MaintenanceStatus"
)

if not exist "%REMOTE_DIR%" mkdir "%REMOTE_DIR%" >nul 2>nul
copy /Y "%PAYLOAD_DIR%\maintenance_status.sh" "%REMOTE_DIR%\" >nul 2>nul
copy /Y "%PAYLOAD_DIR%\Run-MaintenanceStatus.cmd" "%REMOTE_DIR%\" >nul 2>nul
copy /Y "%PAYLOAD_DIR%\Register-MaintenanceStatus-Task.cmd" "%REMOTE_DIR%\" >nul 2>nul

if errorlevel 1 (
    set "PAYLOAD_STATUS=CopyFailed"
) else (
    set "PAYLOAD_STATUS=Staged:%REMOTE_DIR%"
)
exit /b 0

:RegisterRemoteTask
set "HOST=%~1"

if /I "%HOST%"=="%COMPUTERNAME%" (
    schtasks /Create /TN "SysAdminSuite Maintenance Status" /SC ONLOGON /TR "\"%REMOTE_LAUNCHER%\"" /F >nul 2>nul
) else (
    schtasks /Create /S "%HOST%" /TN "SysAdminSuite Maintenance Status" /SC ONLOGON /TR "\"%REMOTE_LAUNCHER%\"" /F >nul 2>nul
)

if errorlevel 1 (
    set "TASK_STATUS=RegisterFailed"
) else (
    set "TASK_STATUS=Registered:%REMOTE_LAUNCHER%"
)
exit /b 0

:WriteReportHeader
> "%REPORT_HTML%" echo ^<!doctype html^>
>> "%REPORT_HTML%" echo ^<html^>^<head^>^<meta charset="utf-8"^>^<title^>Maintenance Status Report^</title^>
>> "%REPORT_HTML%" echo ^<style^>
>> "%REPORT_HTML%" echo body{font-family:Segoe UI,Arial,sans-serif;background:#0f1115;color:#eef2f5;margin:24px;} h1{color:#9be28f;margin-bottom:4px;} h2{color:#d7ffd0;margin-top:28px;} .meta{color:#b7c0c7;} .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin:22px 0;} .card{background:#181d24;border:1px solid #303945;border-radius:14px;padding:14px;box-shadow:0 8px 20px rgba(0,0,0,.25);} .card .label{font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:#aeb8c2;} .card .value{font-size:30px;font-weight:800;margin-top:4px;} .ok{color:#9be28f;} .bad{color:#ff8a80;} .warn{color:#ffd166;} .neutral{color:#9ecbff;} table{border-collapse:collapse;width:100%%;margin-top:18px;} th,td{border:1px solid #384150;padding:8px;text-align:left;vertical-align:top;} th{background:#202733;color:#d7ffd0;} tr:nth-child(even){background:#161b22;} code{color:#9be28f;}
>> "%REPORT_HTML%" echo ^</style^>^</head^>^<body^>
>> "%REPORT_HTML%" echo ^<h1^>SysAdminSuite Maintenance Status Fleet Report^</h1^>
>> "%REPORT_HTML%" echo ^<p class="meta"^>Admin Box: ^<code^>%COMPUTERNAME%^</code^> ^| Hub: ^<code^>%AKBARNATOR_HOST% / Akbarnator^</code^> ^| Generated: ^<code^>%DATE% %TIME%^</code^>^</p^>
>> "%REPORT_HTML%" echo ^<p class="meta"^>Target File: ^<code^>%TARGET_FILE%^</code^>^</p^>
>> "%REPORT_HTML%" echo ^<p class="meta"^>Share strategy: try ^<code^>\\HOST\C$\SUPPORT^</code^> first, then fallback to ^<code^>\\HOST\C$^</code^> and stage under ^<code^>C:\SUPPORT\SysAdminSuite\MaintenanceStatus^</code^>.^</p^>
>> "%REPORT_HTML%" echo ^<section class="cards" id="summaryCards"^>
>> "%REPORT_HTML%" echo ^<div class="card"^>^<div class="label"^>Total Targets^</div^>^<div class="value neutral" id="totalTargets"^>0^</div^>^</div^>
>> "%REPORT_HTML%" echo ^<div class="card"^>^<div class="label"^>Live^</div^>^<div class="value ok" id="liveTargets"^>0^</div^>^</div^>
>> "%REPORT_HTML%" echo ^<div class="card"^>^<div class="label"^>Not Live^</div^>^<div class="value bad" id="notLiveTargets"^>0^</div^>^</div^>
>> "%REPORT_HTML%" echo ^<div class="card"^>^<div class="label"^>C$\SUPPORT OK^</div^>^<div class="value ok" id="supportOk"^>0^</div^>^</div^>
>> "%REPORT_HTML%" echo ^<div class="card"^>^<div class="label"^>C$ Fallback^</div^>^<div class="value warn" id="fallbackUsed"^>0^</div^>^</div^>
>> "%REPORT_HTML%" echo ^<div class="card"^>^<div class="label"^>No Share^</div^>^<div class="value bad" id="noShare"^>0^</div^>^</div^>
>> "%REPORT_HTML%" echo ^<div class="card"^>^<div class="label"^>Payload Staged^</div^>^<div class="value ok" id="payloadStaged"^>0^</div^>^</div^>
>> "%REPORT_HTML%" echo ^<div class="card"^>^<div class="label"^>Task Registered^</div^>^<div class="value ok" id="taskRegistered"^>0^</div^>^</div^>
>> "%REPORT_HTML%" echo ^<div class="card"^>^<div class="label"^>Task Failed^</div^>^<div class="value bad" id="taskFailed"^>0^</div^>^</div^>
>> "%REPORT_HTML%" echo ^</section^>
>> "%REPORT_HTML%" echo ^<table id="resultTable"^>^<thead^>^<tr^>^<th^>Hostname^</th^>^<th^>Mode^</th^>^<th^>Action^</th^>^<th^>Ping^</th^>^<th^>Share^</th^>^<th^>Share Path^</th^>^<th^>Payload^</th^>^<th^>Task^</th^>^<th^>Notes^</th^>^</tr^>^</thead^>^<tbody^>
exit /b 0

:WriteReportRow
set "R_HOST=%~1"
set "R_MODE=%~2"
set "R_ACTION=%~3"
set "R_PING=%~4"
set "R_SHARE=%~5"
set "R_SHAREPATH=%~6"
set "R_PAYLOAD=%~7"
set "R_TASK=%~8"
set "R_NOTES=%~9"
>> "%REPORT_HTML%" echo ^<tr^>^<td^>%R_HOST%^</td^>^<td^>%R_MODE%^</td^>^<td^>%R_ACTION%^</td^>^<td^>%R_PING%^</td^>^<td^>%R_SHARE%^</td^>^<td^>%R_SHAREPATH%^</td^>^<td^>%R_PAYLOAD%^</td^>^<td^>%R_TASK%^</td^>^<td^>%R_NOTES%^</td^>^</tr^>
exit /b 0

:WriteReportFooter
>> "%REPORT_HTML%" echo ^</tbody^>^</table^>
>> "%REPORT_HTML%" echo ^<h2^>Run Guidance^</h2^>
>> "%REPORT_HTML%" echo ^<p^>RemoteReport performs admin-box reporting only. TargetDisplay actions stage payload only when explicitly requested.^</p^>
>> "%REPORT_HTML%" echo ^<p^>For visible target display, the payload must execute in the target's interactive/autologon session. A scheduled task may not display if policy/session context prevents it.^</p^>
>> "%REPORT_HTML%" echo ^<p^>Targets are not assumed to have SysAdminSuite. The controller stages only the maintenance payload when an action requests it.^</p^>
>> "%REPORT_HTML%" echo ^<script^>
>> "%REPORT_HTML%" echo (function(){var rows=[].slice.call(document.querySelectorAll('#resultTable tbody tr'));function txt(r,i){return (r.children[i].textContent||'').trim();}function count(fn){return rows.filter(fn).length;}function set(id,v){document.getElementById(id).textContent=v;}set('totalTargets',rows.length);set('liveTargets',count(function(r){return txt(r,3)==='Pass';}));set('notLiveTargets',count(function(r){return txt(r,3)!=='Pass';}));set('supportOk',count(function(r){return txt(r,4)==='C$SupportPath';}));set('fallbackUsed',count(function(r){return txt(r,4)==='AdminShareFallback';}));set('noShare',count(function(r){return txt(r,4)==='NoShare';}));set('payloadStaged',count(function(r){return txt(r,6).indexOf('Staged:')===0;}));set('taskRegistered',count(function(r){return txt(r,7).indexOf('Registered:')===0;}));set('taskFailed',count(function(r){return txt(r,7)==='RegisterFailed';}));})();
>> "%REPORT_HTML%" echo ^</script^>
>> "%REPORT_HTML%" echo ^</body^>^</html^>
exit /b 0
