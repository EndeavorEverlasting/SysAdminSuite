#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$repairScript = Join-Path -Path $repoRoot -ChildPath 'scripts\Repair-SasAutoLogonTerminalRecoveryDiscoveryRuntime.ps1'
if (-not (Test-Path -LiteralPath $repairScript -PathType Leaf)) { throw "Missing repair script: $repairScript" }

$fixtureSource = @'
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$terminal = 'terminal.json'
$recovered = 'recovered.json'
$file = Get-Item $PSCommandPath
$installPresent = $false
$items = @()
function Get-SasOptionalJsonString { param($Object,[string]$Name) return '' }
function Get-SasInterruptedS4UCandidates {
    if ($true) {
        if (Test-Path -LiteralPath $terminal -PathType Leaf) { continue }
        $items += [pscustomobject][ordered]@{
            install_or_after_evidence_present=$installPresent
            last_write_utc=$file.LastWriteTimeUtc
        }
    }
    return @($items)
}
$candidates = @(Get-SasInterruptedS4UCandidates)
$unsafe = @($candidates | Where-Object { $_.install_or_after_evidence_present })
$resultA = [pscustomobject]@{ schema_version='sas-autologon-s4u-recovery-discovery/v2' }
$resultB = [pscustomobject]@{ schema_version='sas-autologon-s4u-recovery-discovery/v2' }
$resultA
$resultB
'@
$fixtureLf = $fixtureSource.Replace("`r`n","`n")

function Get-LatestEvidence {
    param([Parameter(Mandatory = $true)][string]$EvidenceRoot)
    $path = Get-ChildItem -LiteralPath $EvidenceRoot -Directory |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1 |
        ForEach-Object { Join-Path $_.FullName 'terminal-recovery-discovery-runtime-repair-result.json' }
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Discovery repair evidence missing.' }
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sas-terminal-recovery-discovery-repair-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    foreach ($case in @(
        [pscustomobject]@{ Name='LF'; NewLine="`n" },
        [pscustomobject]@{ Name='CRLF'; NewLine="`r`n" }
    )) {
        $runtimeRoot = Join-Path $tempRoot ('runtime-' + $case.Name)
        $scriptsRoot = Join-Path $runtimeRoot 'scripts'
        $evidenceRoot = Join-Path $tempRoot ('evidence-' + $case.Name)
        New-Item -ItemType Directory -Path $scriptsRoot,$evidenceRoot -Force | Out-Null
        $target = Join-Path $scriptsRoot 'Recover-SasLatestInterruptedAutoLogonS4U.ps1'
        $fixture = if ($case.Name -eq 'CRLF') { $fixtureLf.Replace("`n","`r`n") } else { $fixtureLf }
        [IO.File]::WriteAllText($target,$fixture,(New-Object Text.UTF8Encoding($false)))

        & $repairScript -RuntimeRoot $runtimeRoot -EvidenceRoot $evidenceRoot | Out-Host
        $first = Get-LatestEvidence -EvidenceRoot $evidenceRoot
        if ([string]$first.status -ne 'PASS_REPAIRED') { throw "$($case.Name): expected PASS_REPAIRED, got $($first.status)" }
        if (-not [bool]$first.changed -or -not [bool]$first.parser_valid -or -not [bool]$first.semantic_verification_passed) {
            throw "$($case.Name): repair evidence incomplete"
        }
        foreach ($field in @('git_activity','network_activity','target_contact','target_mutation')) {
            if ([string]$first.$field -ne 'NONE') { throw "$($case.Name): $field must be NONE" }
        }

        $repaired = [IO.File]::ReadAllText($target)
        foreach ($marker in @(
            'S4U_PROBE_CREATE_TIMEOUT',
            'S4U_PROBE_CREATE_TIMEOUT_CONFIRMED_ABSENT',
            'S4U_PROBE_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED',
            'terminal_pilot_recovery_eligible=$terminalPilotRecoveryEligible',
            'terminal_pilot_parse_failed=$terminalPilotParseFailed',
            'Refusing target contact or automatic recovery',
            'sas-autologon-s4u-recovery-discovery/v3'
        )) {
            if (-not $repaired.Contains($marker)) { throw "$($case.Name): missing $marker" }
        }
        if ($repaired.Contains('if (Test-Path -LiteralPath $terminal -PathType Leaf) { continue }')) {
            throw "$($case.Name): old terminal-result skip remains"
        }
        if ($repaired.Contains('sas-autologon-s4u-recovery-discovery/v2')) { throw "$($case.Name): old schema remains" }
        if ($case.Name -eq 'CRLF' -and -not $repaired.Contains("`r`n")) { throw 'CRLF: line ending was not preserved' }
        if ($case.Name -eq 'LF' -and $repaired.Contains("`r`n")) { throw 'LF: unexpected CRLF conversion' }

        & $repairScript -RuntimeRoot $runtimeRoot -EvidenceRoot $evidenceRoot | Out-Host
        $second = Get-LatestEvidence -EvidenceRoot $evidenceRoot
        if ([string]$second.status -ne 'PASS_ALREADY_APPLIED') { throw "$($case.Name): expected PASS_ALREADY_APPLIED, got $($second.status)" }
        if (-not [bool]$second.already_applied -or [bool]$second.changed) { throw "$($case.Name): idempotence evidence incorrect" }
    }
    Write-Host 'PASS: terminal recovery discovery runtime repair fixtures (LF + CRLF + idempotence)' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
