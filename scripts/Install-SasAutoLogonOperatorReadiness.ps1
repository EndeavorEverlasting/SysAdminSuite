#Requires -Version 5.1
<#
.SYNOPSIS
Install cross-user AutoLogon operator-readiness surfaces on a SysAdminSuite controller.

.DESCRIPTION
This is a controller-local setup step. It requires the already-installed machine-wide universal launcher
and the already-prepared C:\SASAL sealed runtime. It does not contact a target or start a deployment.

The installer:
- requires an elevated administrator token;
- requires the universal launcher under ProgramData and a machine PATH entry;
- grants BUILTIN\Users read/execute on the installer-owned ProgramData bin;
- installs the readiness verifier beside sas.cmd;
- creates a Public Desktop AutoLogon Remote CMD that delegates to the existing network-aware dispatcher;
- creates a Public Documents evidence directory that standard users may update.

The Public Documents receipt is evidence only. It is never runtime, manifest, deployment, or authorization authority.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-SasPathContains {
    param(
        [AllowNull()][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Expected
    )
    $expectedNormalized = $Expected.Trim().TrimEnd('\')
    foreach ($segment in @(([string]$PathValue) -split ';')) {
        $candidate = $segment.Trim().Trim('"').TrimEnd('\')
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            $candidate.Equals($expectedNormalized,[StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Invoke-SasIcacls {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Grant
    )
    $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
    if (-not (Test-Path -LiteralPath $icacls -PathType Leaf)) {
        throw "Required Windows ACL utility is missing: $icacls"
    }
    & $icacls $Path '/grant' $Grant | Out-Host
    $aclExit = $global:LASTEXITCODE
    if ($aclExit -ne 0) {
        throw "icacls failed for $Path with exit code $aclExit"
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'AUTOLOGON_OPERATOR_READINESS_ADMIN_REQUIRED: run this installer from an elevated administrator terminal.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceVerifier = Join-Path $repoRoot 'scripts\Test-SasAutoLogonOperatorReadiness.ps1'
if (-not (Test-Path -LiteralPath $sourceVerifier -PathType Leaf)) {
    throw "Readiness verifier is missing: $sourceVerifier"
}

$programData = if ([string]::IsNullOrWhiteSpace([string]$env:ProgramData)) { 'C:\ProgramData' } else { $env:ProgramData }
$installRoot = Join-Path $programData 'SysAdminSuite\bin'
$runtimeRoot = 'C:\SASAL'
$requiredInstalled = @(
    (Join-Path $installRoot 'sas.cmd'),
    (Join-Path $installRoot 'Invoke-SasNetworkAwareField.ps1')
)
$requiredRuntime = @(
    (Join-Path $runtimeRoot 'scripts\Resolve-SasAutoLogonManifestAuthority.ps1'),
    (Join-Path $runtimeRoot 'scripts\Test-SasAutoLogonRuntimeSeal.ps1'),
    (Join-Path $runtimeRoot '.git\sas-autologon-short-runtime.json')
)
foreach ($required in @($requiredInstalled + $requiredRuntime)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "AUTOLOGON_OPERATOR_READINESS_PREREQUISITE_MISSING: $required"
    }
}

$machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
if (-not (Test-SasPathContains -PathValue $machinePath -Expected $installRoot)) {
    $newMachinePath = if ([string]::IsNullOrWhiteSpace([string]$machinePath)) {
        $installRoot
    }
    else {
        ([string]$machinePath).TrimEnd(';') + ';' + $installRoot
    }
    [Environment]::SetEnvironmentVariable('Path',$newMachinePath,'Machine')
    $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
}
if (-not (Test-SasPathContains -PathValue $machinePath -Expected $installRoot)) {
    throw "AUTOLOGON_OPERATOR_READINESS_MACHINE_PATH_FAILED: $installRoot is not present in Machine PATH."
}

$verifierDestination = Join-Path $installRoot 'Test-SasAutoLogonOperatorReadiness.ps1'
Copy-Item -LiteralPath $sourceVerifier -Destination $verifierDestination -Force

$commonDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
if ([string]::IsNullOrWhiteSpace($commonDesktop)) { $commonDesktop = 'C:\Users\Public\Desktop' }
$commonDocuments = [Environment]::GetFolderPath('CommonDocuments')
if ([string]::IsNullOrWhiteSpace($commonDocuments)) { $commonDocuments = 'C:\Users\Public\Documents' }
$evidenceRoot = Join-Path $commonDocuments 'SysAdminSuite'
New-Item -ItemType Directory -Path $commonDesktop -Force | Out-Null
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null

# S-1-5-32-545 is BUILTIN\Users. Use the SID form so ACL setup is not tied to Windows display language.
Invoke-SasIcacls -Path $installRoot -Grant '*S-1-5-32-545:(OI)(CI)(RX)'
# The sealed controller runtime contains code/evidence authority but no credential material. Standard users need
# read/execute only; this ACL changes no tracked bytes and grants no write permission.
Invoke-SasIcacls -Path $runtimeRoot -Grant '*S-1-5-32-545:(OI)(CI)(RX)'
# This directory contains public-safe, non-authoritative receipts; standard users need bounded update access.
Invoke-SasIcacls -Path $evidenceRoot -Grant '*S-1-5-32-545:(OI)(CI)(M)'

$desktopCmdPath = Join-Path $commonDesktop 'SysAdminSuite - AutoLogon Remote.cmd'
$desktopCmd = @'
@echo off
setlocal EnableExtensions DisableDelayedExpansion
title SysAdminSuite - AutoLogon Remote
cls

echo ================================================================
echo  SYSADMINSUITE - AUTOLOGON REMOTE
echo ================================================================
echo  Uses the installed SysAdminSuite network-aware AutoLogon route.
echo  No target is stored in this launcher. Enter one authorized host.
echo ================================================================
echo.

set "SAS_AUTOLOGON_ENTRYPOINT=%ProgramData%\SysAdminSuite\bin\Invoke-SasNetworkAwareField.ps1"
if not exist "%SAS_AUTOLOGON_ENTRYPOINT%" (
  echo ERROR: Machine-wide SysAdminSuite launcher is missing.
  echo Run the approved SysAdminSuite refresh/readiness installation first.
  set "SAS_EXIT=10"
  goto finish
)

set "SAS_AUTOLOGON_TARGET="
set /p "SAS_AUTOLOGON_TARGET=Authorized hostname or FQDN: "
if not defined SAS_AUTOLOGON_TARGET (
  echo ERROR: No target entered.
  set "SAS_EXIT=2"
  goto finish
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$t=[string]$env:SAS_AUTOLOGON_TARGET; if($t -notmatch '^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$'){Write-Host 'ERROR: Target must be a hostname or FQDN.' -ForegroundColor Red; exit 2}; & $env:SAS_AUTOLOGON_ENTRYPOINT 'autologon' 'Remote' $t; $e=$global:LASTEXITCODE; if($null -eq $e){$e=1}; exit [int]$e"
set "SAS_EXIT=%ERRORLEVEL%"

:finish
if not "%SAS_EXIT%"=="0" (
  echo.
  echo AutoLogon Remote did not finish successfully.
  echo Preserve the SysAdminSuite evidence shown by the command; do not retry blindly.
  echo.
  pause
)
endlocal & exit /b %SAS_EXIT%
'@
[IO.File]::WriteAllText($desktopCmdPath,$desktopCmd,(New-Object Text.UTF8Encoding($false)))
Invoke-SasIcacls -Path $desktopCmdPath -Grant '*S-1-5-32-545:(RX)'

Write-Host 'AutoLogon operator-readiness surfaces installed.' -ForegroundColor Green
Write-Host "Machine launcher root: $installRoot"
Write-Host "Readiness verifier: $verifierDestination"
Write-Host "Public Desktop command: $desktopCmdPath"
Write-Host "Public readiness evidence: $evidenceRoot"
Write-Host 'No network activity, target contact, AutoLogon mutation, or deployment was performed by this installer.' -ForegroundColor Green
Write-Host ''
Write-Host 'NEXT STANDARD-USER PROOF:' -ForegroundColor Cyan
Write-Host ('powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -RequireStandardUser' -f $verifierDestination)
