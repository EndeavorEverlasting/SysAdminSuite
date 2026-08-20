@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Printer Mapping
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_PRINTER_RUNTIME=%~dp0"

rem Northwell quick mapper.
rem SYSTEM-WIDE for ALL users. NO TEST PAGE. Reversible changes produce UndoPlan.json.
rem Primary transport uses canonical administrative-share staging + SYSTEM Task Scheduler.
rem The resilient wrapper delegates by relative path to Start-NorthwellPrinterMapping.ps1 -Action Map first.
rem If fresh evidence proves staging failed before mutation, the resilient wrapper may
rem use shareless SYSTEM Task Scheduler + Remote Registry HKLM proof instead.
rem The trusted launcher verifies resilient mapping and active-user helper files are tracked and exactly at runtime HEAD before execution.
rem Phase 2 follows the successful machine-wide transport: canonical staging stays canonical;
rem shareless machine-wide proof gets shareless InteractiveToken + Remote Registry HKU proof.
rem No reachability sweep. No direct-IP fallback. No blind remap after ambiguous failure.

"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if not "%ERRORLEVEL%"=="0" (
    echo Requesting Administrator rights...
    set "SAS_NORTHWELL_PRINTER_LAUNCHER=%~f0"
    "%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('""{0}""' -f $env:SAS_NORTHWELL_PRINTER_LAUNCHER)) -Verb RunAs -PassThru -Wait; exit $p.ExitCode } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
    set "SAS_ELEVATED_RC=!ERRORLEVEL!"
    exit /b !SAS_ELEVATED_RC!
)

"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $root=[IO.Path]::GetFullPath($env:SAS_PRINTER_RUNTIME); $paths=@('mapping\Invoke-NorthwellPrinterResilientQuick.ps1','mapping\Invoke-NorthwellPrinterTaskRegistryFallback.ps1','mapping\Confirm-NorthwellPrinterActiveUserMaterializationResilient.ps1','mapping\Invoke-NorthwellPrinterSharelessActiveUser.ps1'); $gitCommand=Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1; if(-not $gitCommand){$gitCommand=Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1}; $git=if($gitCommand){$gitCommand.Source}else{$null}; if(-not $git){foreach($candidate in @((Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),(Join-Path $env:ProgramFiles 'Git\bin\git.exe'),(Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe'))){if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)){$git=$candidate;break}}}; if(-not $git){Write-Error 'Git for Windows is required to verify the resilient printer helpers.';exit 1}; foreach($path in $paths){& $git -C $root ls-files --error-unmatch -- $path *> $null; if($LASTEXITCODE -ne 0){Write-Error ('Required resilient printer helper is not tracked: '+$path);exit 1}; & $git -C $root diff --quiet HEAD -- $path; if($LASTEXITCODE -ne 0){Write-Error ('Required resilient printer helper differs from runtime HEAD: '+$path);exit 1}}; exit 0"
if not "%ERRORLEVEL%"=="0" (
    echo Printer runtime integrity verification failed. Nothing was mapped.
    exit /b 1
)

echo Northwell system-wide printer mapping
"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Invoke-NorthwellPrinterResilientQuick.ps1" -Action Map
set "SAS_RC=%ERRORLEVEL%"

if "%SAS_RC%"=="0" (
    echo.
    echo Verifying immediate availability for any user already logged on...
    "%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Confirm-NorthwellPrinterActiveUserMaterializationResilient.ps1"
    set "SAS_RC=!ERRORLEVEL!"
)

echo.
if "%SAS_RC%"=="0" (
    echo Done. Machine-wide registration is proven; any active user session was finalized and verified.
) else (
    echo Mapping is NOT complete for the current session. Review the error and evidence above. Do not remap blindly.
)
echo.
pause
exit /b %SAS_RC%
