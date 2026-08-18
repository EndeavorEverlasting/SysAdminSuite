#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$repairScript = Join-Path -Path $repoRoot -ChildPath 'scripts\Repair-SasAutoLogonS4UCreateTimeoutRuntime.ps1'
$sourcePilot = Join-Path -Path $repoRoot -ChildPath 'scripts\Invoke-SasAutoLogonKerberosS4UPilot.ps1'
foreach ($required in @($repairScript,$sourcePilot)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing required fixture dependency: $required"
    }
}
$sourcePilotLf = [IO.File]::ReadAllText($sourcePilot).Replace("`r`n", "`n")
if (-not $sourcePilotLf.Contains('S4U_${modeUpper}_CREATE_TIMEOUT')) {
    throw 'Tracked S4U pilot no longer contains the pre-repair create-timeout anchor.'
}
if ($sourcePilotLf.Contains('S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_PRESENT')) {
    throw 'Tracked S4U pilot already contains the repair; fixture must exercise the protected-runtime transformation.'
}

function Get-LatestEvidence {
    param([Parameter(Mandatory = $true)][string]$EvidenceRoot)
    $result = Get-ChildItem -LiteralPath $EvidenceRoot -Directory |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1 |
        ForEach-Object { Join-Path -Path $_.FullName -ChildPath 's4u-create-timeout-runtime-repair-result.json' }
    if ([string]::IsNullOrWhiteSpace([string]$result) -or -not (Test-Path -LiteralPath $result -PathType Leaf)) {
        throw "Repair evidence was not produced under $EvidenceRoot"
    }
    Get-Content -LiteralPath $result -Raw -Encoding UTF8 | ConvertFrom-Json
}

$tempRoot = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ('sas-s4u-create-timeout-repair-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    foreach ($case in @(
        [pscustomobject]@{ Name='LF'; NewLine="`n" },
        [pscustomobject]@{ Name='CRLF'; NewLine="`r`n" }
    )) {
        $runtimeRoot = Join-Path -Path $tempRoot -ChildPath ('runtime-' + $case.Name)
        $scriptsRoot = Join-Path -Path $runtimeRoot -ChildPath 'scripts'
        $evidenceRoot = Join-Path -Path $tempRoot -ChildPath ('evidence-' + $case.Name)
        New-Item -ItemType Directory -Path $scriptsRoot,$evidenceRoot -Force | Out-Null
        $pilot = Join-Path -Path $scriptsRoot -ChildPath 'Invoke-SasAutoLogonKerberosS4UPilot.ps1'
        $fixture = if ($case.Name -eq 'CRLF') { $sourcePilotLf.Replace("`n", "`r`n") } else { $sourcePilotLf }
        [IO.File]::WriteAllText($pilot, $fixture, (New-Object Text.UTF8Encoding($false)))

        & $repairScript -RuntimeRoot $runtimeRoot -EvidenceRoot $evidenceRoot | Out-Host
        $first = Get-LatestEvidence -EvidenceRoot $evidenceRoot
        if ([string]$first.status -ne 'PASS_REPAIRED') { throw "$($case.Name): expected PASS_REPAIRED, got $($first.status)" }
        if (-not [bool]$first.changed -or -not [bool]$first.parser_valid -or -not [bool]$first.semantic_verification_passed) {
            throw "$($case.Name): repair evidence did not prove changed/parser/semantic success"
        }
        foreach ($field in @('git_activity','network_activity','target_contact','target_mutation')) {
            if ([string]$first.$field -ne 'NONE') { throw "$($case.Name): $field must remain NONE" }
        }

        $repaired = [IO.File]::ReadAllText($pilot)
        foreach ($marker in @(
            'create_timeout_confirmation = $null',
            'S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_PRESENT',
            'S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMED_ABSENT',
            'S4U_${modeUpper}_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED',
            "'/Query','/S',`$Target,'/TN',`$TaskName",
            "elseif ([int]`$create.exit_code -ne 0)"
        )) {
            if (-not $repaired.Contains($marker)) { throw "$($case.Name): repaired fixture missing $marker" }
        }
        $legacyImmediateThrow = @'
        if ([bool]$create.timed_out) {
            $lifecycle.classification = "S4U_${modeUpper}_CREATE_TIMEOUT"
            throw "S4U $Mode task creation timed out after $NativeTimeoutSeconds seconds."
        }
'@.Replace("`r`n", "`n")
        if ($repaired.Replace("`r`n", "`n").Contains($legacyImmediateThrow)) {
            throw "$($case.Name): legacy immediate create-timeout throw remains"
        }
        if ($case.Name -eq 'CRLF' -and -not $repaired.Contains("`r`n")) { throw 'CRLF: line ending was not preserved' }
        if ($case.Name -eq 'LF' -and $repaired.Contains("`r`n")) { throw 'LF: unexpected CRLF conversion' }

        & $repairScript -RuntimeRoot $runtimeRoot -EvidenceRoot $evidenceRoot | Out-Host
        $second = Get-LatestEvidence -EvidenceRoot $evidenceRoot
        if ([string]$second.status -ne 'PASS_ALREADY_APPLIED') { throw "$($case.Name): expected PASS_ALREADY_APPLIED, got $($second.status)" }
        if (-not [bool]$second.already_applied -or [bool]$second.changed) {
            throw "$($case.Name): idempotence evidence is incorrect"
        }
    }

    Write-Host 'PASS: S4U create-timeout runtime repair Windows fixtures (tracked pilot LF + CRLF + idempotence)' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
