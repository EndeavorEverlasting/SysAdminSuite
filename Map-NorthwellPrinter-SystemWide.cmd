@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Printer Mapping
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_PRINTER_RUNTIME=%~dp0"

rem Northwell quick mapper.
rem SYSTEM-WIDE for ALL users. NO TEST PAGE. Reversible changes produce UndoPlan.json.
rem The operator wrapper preserves the already-green resilient mapper and active-user finalizer.
rem Invoke-NorthwellPrinterResilientQuick.ps1 delegates to Start-NorthwellPrinterMapping.ps1 first.
rem Durable run history is written only to the invoking user's LOCALAPPDATA on this admin box.
rem Target-side transport artifacts remain transient and are cleaned by the owning mapper.
rem No reachability sweep. No direct-IP fallback. No blind remap after ambiguous failure.

"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if not "%ERRORLEVEL%"=="0" (
    echo Requesting Administrator rights...
    set "SAS_NORTHWELL_PRINTER_LAUNCHER=%~f0"
    "%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('""{0}""' -f $env:SAS_NORTHWELL_PRINTER_LAUNCHER)) -Verb RunAs -PassThru -Wait; exit $p.ExitCode } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
    set "SAS_ELEVATED_RC=!ERRORLEVEL!"
    exit /b !SAS_ELEVATED_RC!
)

"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $root=[IO.Path]::GetFullPath($env:SAS_PRINTER_RUNTIME); $paths=@('mapping\Invoke-NorthwellPrinterOperatorRun.ps1','scripts\SasPrinterRunJournal.psm1','mapping\Invoke-NorthwellPrinterResilientQuick.ps1','mapping\Invoke-NorthwellPrinterTaskRegistryFallback.ps1','mapping\Confirm-NorthwellPrinterActiveUserMaterializationResilient.ps1','mapping\Invoke-NorthwellPrinterSharelessActiveUser.ps1'); $gitCommand=Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1; if(-not $gitCommand){$gitCommand=Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1}; $git=if($gitCommand){$gitCommand.Source}else{$null}; if(-not $git){foreach($candidate in @((Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),(Join-Path $env:ProgramFiles 'Git\bin\git.exe'),(Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe'))){if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)){$git=$candidate;break}}}; if(-not $git){Write-Error 'Git for Windows is required to verify the printer operator runtime.';exit 1}; foreach($path in $paths){& $git -C $root ls-files --error-unmatch -- $path *> $null; if($LASTEXITCODE -ne 0){Write-Error ('Required printer operator dependency is not tracked: '+$path);exit 1}; & $git -C $root diff --quiet HEAD -- $path; if($LASTEXITCODE -ne 0){Write-Error ('Required printer operator dependency differs from runtime HEAD: '+$path);exit 1}}; exit 0"
if not "%ERRORLEVEL%"=="0" (
    echo Printer runtime integrity verification failed. Nothing was mapped.
    echo.
    pause
    exit /b 1
)

echo Northwell system-wide printer mapping
"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Invoke-NorthwellPrinterOperatorRun.ps1" -Action Map
set "SAS_RC=!ERRORLEVEL!"

echo.
if "!SAS_RC!"=="0" (
    echo Printer run complete. The terminal remains open and the local admin trail is shown above.
) else (
    echo Printer run did not complete. The terminal remains open; review the local admin trail shown above.
)
echo.
pause
exit /b !SAS_RC!
