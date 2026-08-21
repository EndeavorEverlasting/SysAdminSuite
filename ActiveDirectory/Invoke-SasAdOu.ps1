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

function Write-SasAdOuUsage {
    Write-Host 'SysAdminSuite Active Directory OU workflow' -ForegroundColor Cyan
    Write-Host '  sas ad ou probe HOST01 [HOST02 ...]'
    Write-Host '      Read-only current OU + Imprivata GPO link/inheritance evidence and ticket notes.'
    Write-Host '  sas ad ou plan HOST "TARGET_OU_DN"'
    Write-Host '      Existing reversible OU engine in plan-only mode. No AD mutation.'
    Write-Host '  sas ad ou apply HOST "TARGET_OU_DN" CHANGE_REFERENCE'
    Write-Host '      Existing one-host high-impact engine: Apply + ChangeReference + ShouldProcess + post-move verification.'
    Write-Host ''
    Write-Host 'The probe may identify a unique managed policy-linked OU candidate, but it never authorizes or automatically selects a move target.' -ForegroundColor Yellow
}

if ($argsClean.Count -lt 2 -or ([string]$argsClean[0]).Trim().ToLowerInvariant() -ne 'ou') {
    Write-SasAdOuUsage
    exit 2
}

$mode = ([string]$argsClean[1]).Trim().ToLowerInvariant()
& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $networkGate -Purpose "Active Directory OU $mode" -NonInteractive
$networkExit = [int]$global:LASTEXITCODE
if ($networkExit -ne 0) { exit $networkExit }

switch ($mode) {
    'probe' {
        $targets = @($argsClean | Select-Object -Skip 2)
        if ($targets.Count -lt 1 -or $targets.Count -gt 25) {
            Write-Host 'Usage: sas ad ou probe HOST01 [HOST02 ...]' -ForegroundColor Red
            exit 2
        }
        & $probePath -ComputerName $targets -PolicyKeyword 'Imprivata'
        exit $LASTEXITCODE
    }

    'plan' {
        if ($argsClean.Count -ne 4) {
            Write-Host 'Usage: sas ad ou plan HOST "TARGET_OU_DN"' -ForegroundColor Red
            exit 2
        }
        $hostName = [string]$argsClean[2]
        $targetOu = [string]$argsClean[3]
        Write-Host 'OU mode: PLAN ONLY. Target mutation is disabled.' -ForegroundColor Green
        & $movePath -ComputerName $hostName -TargetOU $targetOu
        exit 0
    }

    'apply' {
        if ($argsClean.Count -ne 5) {
            Write-Host 'Usage: sas ad ou apply HOST "TARGET_OU_DN" CHANGE_REFERENCE' -ForegroundColor Red
            exit 2
        }
        $hostName = [string]$argsClean[2]
        $targetOu = [string]$argsClean[3]
        $changeReference = [string]$argsClean[4]
        Write-Host 'OU mode: APPLY. Existing one-host ceiling, high-impact confirmation, source re-read, post-move verification, and rollback generation remain authoritative.' -ForegroundColor Yellow
        & $movePath -ComputerName $hostName -TargetOU $targetOu -Apply -ChangeReference $changeReference
        exit 0
    }

    default {
        Write-SasAdOuUsage
        exit 2
    }
}
