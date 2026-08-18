#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$repairScript = Join-Path -Path $repoRoot -ChildPath 'scripts\Repair-SasAutoLogonTerminalProbeRecoveryRuntime.ps1'
if (-not (Test-Path -LiteralPath $repairScript -PathType Leaf)) { throw "Missing repair script: $repairScript" }

$fixtureSource = @'
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$terminalResult = 'terminal.json'
$TaskName = 'SysAdminSuite-AutoLogonS4UProbe-0123456789abcdef0123456789abcdef'
if (Test-Path -LiteralPath $terminalResult -PathType Leaf) { throw 'A terminal S4U pilot result already exists; use that result instead of interrupted recovery.' }
$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-s4u-interrupted-recovery/v2'
    status = 'COMPLETED'
    terminal_pilot_result_present = $false
    installer_phase_entered = $false
}
$result
'@
$fixtureLf = $fixtureSource.Replace("`r`n","`n")

function Get-LatestEvidence {
    param([Parameter(Mandatory = $true)][string]$EvidenceRoot)
    $path = Get-ChildItem -LiteralPath $EvidenceRoot -Directory |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1 |
        ForEach-Object { Join-Path $_.FullName 'terminal-probe-recovery-runtime-repair-result.json' }
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Recovery repair evidence missing.' }
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sas-terminal-probe-recovery-repair-test-' + [guid]::NewGuid().ToString('N'))
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
        $target = Join-Path $scriptsRoot 'Complete-SasInterruptedAutoLogonS4URecovery.ps1'
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
            'S4U_PROBE_CREATE_TIMEOUT_CONFIRMED_ABSENT',
            'S4U_PROBE_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED',
            'Terminal S4U pilot probe task identity does not match requested recovery task',
            'terminal_pilot_recovery_eligible = $terminalPilotRecoveryEligible',
            "schema_version = 'sas-autologon-s4u-interrupted-recovery/v3'"
        )) {
            if (-not $repaired.Contains($marker)) { throw "$($case.Name): missing $marker" }
        }
        if ($repaired.Contains('A terminal S4U pilot result already exists; use that result instead of interrupted recovery.')) {
            throw "$($case.Name): old terminal-result refusal remains"
        }
        if ($case.Name -eq 'CRLF' -and -not $repaired.Contains("`r`n")) { throw 'CRLF: line ending was not preserved' }
        if ($case.Name -eq 'LF' -and $repaired.Contains("`r`n")) { throw 'LF: unexpected CRLF conversion' }

        & $repairScript -RuntimeRoot $runtimeRoot -EvidenceRoot $evidenceRoot | Out-Host
        $second = Get-LatestEvidence -EvidenceRoot $evidenceRoot
        if ([string]$second.status -ne 'PASS_ALREADY_APPLIED') { throw "$($case.Name): expected PASS_ALREADY_APPLIED, got $($second.status)" }
        if (-not [bool]$second.already_applied -or [bool]$second.changed) { throw "$($case.Name): idempotence evidence incorrect" }
    }
    Write-Host 'PASS: terminal probe-timeout recovery runtime repair fixtures (LF + CRLF + idempotence)' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
