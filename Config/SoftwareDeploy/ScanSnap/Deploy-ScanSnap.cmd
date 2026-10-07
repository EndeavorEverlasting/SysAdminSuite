@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Field fast paths deliberately bypass the legacy combinatorial argument parser.
rem They own Northwell network authority, exact FQDN binding, canonical transport
rem preflight, Admin-Box confirmation, deployment, detection, and evidence.
if /I "%~1"=="/FIELDPREFLIGHT" (
  if not "%~2"=="" (
    echo ERROR: /FIELDPREFLIGHT takes no additional arguments. Edit hosts_field.txt or use the dedicated field entrypoint.
    exit /b 1
  )
  call "%~dp0Preflight-ScanSnap-Field.cmd"
  exit /b !ERRORLEVEL!
)
if /I "%~1"=="/FIELD" (
  if not "%~2"=="" (
    echo ERROR: /FIELD takes no additional arguments. Edit hosts_field.txt or use the dedicated field entrypoint.
    exit /b 1
  )
  call "%~dp0Deploy-ScanSnap-Field.cmd"
  exit /b !ERRORLEVEL!
)

rem ------------------------------------------------------------------------------
rem Deploy-ScanSnap.cmd — Admin Box 1 (LPW003ASI173) entrypoint.
rem Logic lives in Deploy-ScanSnap.ps1 (no duplicated deploy logic here).
rem cmd.exe treats '=' as an argument delimiter, so /HOSTSFILE=file may arrive
rem as /HOSTSFILE and file. This parser accepts /KEY=VALUE and /KEY VALUE.
rem ------------------------------------------------------------------------------
set "LIST="
set "HOSTSFILE="
set "WHATIF="
set "DNSSUFFIX="
set "PACKAGE=%~dp0"
set "MAXWAIT=300"
set "POLL=5"

:ParseLoop
if "%~1"=="" goto ParseDone
set "ARG=%~1"
if /I "!ARG!"=="/WHATIF" (
  set "WHATIF=1"
  shift
  goto ParseLoop
)
if "!ARG:~0,1!" NEQ "/" (
  echo ERROR: Argument "!ARG!" does not start with '/'. Expected /KEY=VALUE or /KEY VALUE
  exit /b 1
)
set "KV=!ARG:~1!"
set "K="
set "V="
for /f "tokens=1,* delims==" %%K in ("!KV!") do (
  set "K=%%~K"
  set "V=%%~L"
)
if not defined V (
  if not "%~2"=="" (
    set "NEXT=%~2"
    if /I not "!NEXT!"=="/WHATIF" if "!NEXT:~0,1!" NEQ "/" (
      set "V=!NEXT!"
      shift
    )
  )
)
if /I "!K!"=="LIST" set "LIST=!V!"
if /I "!K!"=="HOSTSFILE" set "HOSTSFILE=!V!"
if /I "!K!"=="DNSSUFFIX" set "DNSSUFFIX=!V!"
if /I "!K!"=="PACKAGE" set "PACKAGE=!V!"
if /I "!K!"=="MAXWAIT" set "MAXWAIT=!V!"
if /I "!K!"=="POLL" set "POLL=!V!"
if /I "!K!"=="WHATIF" set "WHATIF=1"
shift
goto ParseLoop
:ParseDone

rem Trailing backslash inside quoted "-PackageRoot \"C:\path\"" escapes the quote.
rem Keep PACKAGE_DIR without trailing slash for safe quoting.
if "!PACKAGE:~-1!"=="\" set "PACKAGE=!PACKAGE:~0,-1!"
set "PS1=!PACKAGE!\Deploy-ScanSnap.ps1"
if not exist "!PS1!" (
  echo ERROR: Engine not found: !PS1!
  exit /b 1
)

set "HF="
if defined HOSTSFILE (
  if exist "!HOSTSFILE!" (
    set "HF=!HOSTSFILE!"
  ) else if exist "!PACKAGE!\!HOSTSFILE!" (
    set "HF=!PACKAGE!\!HOSTSFILE!"
  ) else (
    echo ERROR: Hosts file not found: !HOSTSFILE!
    exit /b 1
  )
)

echo Launching Deploy-ScanSnap.ps1 from Admin Box control plane...

rem Avoid nested delayed-expansion quotes; branch explicit argument sets.
if defined WHATIF (
  if defined HF (
    if defined LIST (
      if defined DNSSUFFIX (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL! -HostsFile "!HF!" -ComputerList !LIST! -DnsSuffix "!DNSSUFFIX!" -WhatIfPreferenceOverride
      ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL! -HostsFile "!HF!" -ComputerList !LIST! -WhatIfPreferenceOverride
      )
    ) else if defined DNSSUFFIX (
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL! -HostsFile "!HF!" -DnsSuffix "!DNSSUFFIX!" -WhatIfPreferenceOverride
    ) else (
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL! -HostsFile "!HF!" -WhatIfPreferenceOverride
    )
  ) else if defined LIST (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL! -ComputerList !LIST! -WhatIfPreferenceOverride
  ) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL! -WhatIfPreferenceOverride
  )
) else (
  if defined HF (
    if defined LIST (
      if defined DNSSUFFIX (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL! -HostsFile "!HF!" -ComputerList !LIST! -DnsSuffix "!DNSSUFFIX!"
      ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL! -HostsFile "!HF!" -ComputerList !LIST!
      )
    ) else if defined DNSSUFFIX (
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL! -HostsFile "!HF!" -DnsSuffix "!DNSSUFFIX!"
    ) else (
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL! -HostsFile "!HF!"
    )
  ) else if defined LIST (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL! -ComputerList !LIST!
  ) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -PackageRoot "!PACKAGE!" -MaxWaitSeconds !MAXWAIT! -PollSeconds !POLL!
  )
)

set "RC=!ERRORLEVEL!"
echo Deploy-ScanSnap.ps1 exit code: !RC!
exit /b !RC!
