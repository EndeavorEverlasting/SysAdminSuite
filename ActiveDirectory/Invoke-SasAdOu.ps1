#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [AllowEmptyString()]
    [string[]]$Arguments
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$networkGate = Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
$probePath = Join-Path $repoRoot 'ActiveDirectory\Probe-ComputerOuPolicy.ps1'
$movePath = Join-Path $repoRoot 'ActiveDirectory\Move-Computers-To-OU.ps1'
foreach ($required in @($networkGate,$probePath,$movePath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing AD/OU dependency: $required" }
}

$argsClean = @($Arguments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

function Test-SasAdHostName {
    param([AllowNull()][string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$'
}

function Test-SasApprovedManagedTargetOuText {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $forbiddenPattern = '(?i)(?:^|,)OU=(?:Workstations|Shared_Workstations),OU=_Workstations(?:,|$)'
    if ($Value -match $forbiddenPattern) { return $false }
    $managedPattern = '(?i)(?:^|,)OU=(?:Managed|Managed_Shared),OU=_Workstations(?:,|$)'
    return [bool]($Value -match $managedPattern)
}

function Write-SasAdOuUsage {
    Write-Host 'SysAdminSuite Active Directory OU workflow' -ForegroundColor Cyan
    Write-Host '  sas ad ou probe HOST01 [HOST02 ...]'
    Write-Host '      Read-only current OU + Imprivata OU/GPO link/inheritance evidence and ticket notes.'
    Write-Host '  sas ad ou plan HOST "TARGET_OU_DN"'
    Write-Host '      Existing reversible OU engine in plan-only mode. No AD mutation.'
    Write-Host '  sas ad ou apply HOST "TARGET_OU_DN" CHANGE_REFERENCE'
    Write-Host '      Existing one-host high-impact engine: Apply + ChangeReference + ShouldProcess + post-move verification.'
    Write-Host ''
    Write-Host 'The probe may identify corroborated managed OU evidence, but it never authorizes or automatically executes a move.' -ForegroundColor Yellow
}

if ($argsClean.Count -lt 2 -or ([string]$argsClean[0]).Trim().ToLowerInvariant() -ne 'ou') {
    Write-SasAdOuUsage
    exit 2
}

$mode = ([string]$argsClean[1]).Trim().ToLowerInvariant()
$targets = @()
$hostName = $null
$targetOu = $null
$changeReference = $null
switch ($mode) {
    'probe' {
        $targets = @($argsClean | Select-Object -Skip 2)
        if ($targets.Count -lt 1 -or $targets.Count -gt 25 -or @($targets | Where-Object { -not (Test-SasAdHostName -Value ([string]$_)) }).Count -gt 0) {
            Write-Host 'Usage: sas ad ou probe HOST01 [HOST02 ...]' -ForegroundColor Red
            exit 2
        }
    }
    'plan' {
        if ($argsClean.Count -ne 4) { Write-Host 'Usage: sas ad ou plan HOST "TARGET_OU_DN"' -ForegroundColor Red; exit 2 }
        $hostName = [string]$argsClean[2]
        $targetOu = [string]$argsClean[3]
        if (-not (Test-SasAdHostName -Value $hostName) -or -not (Test-SasApprovedManagedTargetOuText -Value $targetOu)) {
            Write-Host 'Plan requires one valid hostname and an approved managed workstation OU DN.' -ForegroundColor Red
            exit 2
        }
    }
    'apply' {
        if ($argsClean.Count -ne 5) { Write-Host 'Usage: sas ad ou apply HOST "TARGET_OU_DN" CHANGE_REFERENCE' -ForegroundColor Red; exit 2 }
        $hostName = [string]$argsClean[2]
        $targetOu = [string]$argsClean[3]
        $changeReference = [string]$argsClean[4]
        if (-not (Test-SasAdHostName -Value $hostName) -or
            -not (Test-SasApprovedManagedTargetOuText -Value $targetOu) -or
            [string]::IsNullOrWhiteSpace($changeReference)) {
            Write-Host 'Apply requires one valid hostname, an approved managed workstation OU DN, and a non-empty change reference.' -ForegroundColor Red
            exit 2
        }
    }
    default {
        Write-SasAdOuUsage
        exit 2
    }
}

& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $networkGate -Purpose "Active Directory OU $mode" -NonInteractive
$networkExit = [int]$global:LASTEXITCODE
if ($networkExit -ne 0) { exit $networkExit }

switch ($mode) {
    'probe' {
        # Keep this in-process so Windows PowerShell 5.1 binds the explicit string[] correctly.
        & $probePath -ComputerName $targets -PolicyKeyword 'Imprivata'
        exit $LASTEXITCODE
    }
    'plan' {
        Write-Host 'OU mode: PLAN ONLY. Target mutation is disabled.' -ForegroundColor Green
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $movePath -ComputerName $hostName -TargetOU $targetOu
        exit ([int]$global:LASTEXITCODE)
    }
    'apply' {
        Write-Host 'OU mode: APPLY. Existing one-host ceiling, high-impact confirmation, source re-read, post-move verification, and rollback generation remain authoritative.' -ForegroundColor Yellow
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $movePath -ComputerName $hostName -TargetOU $targetOu -Apply -ChangeReference $changeReference
        exit ([int]$global:LASTEXITCODE)
    }
}
