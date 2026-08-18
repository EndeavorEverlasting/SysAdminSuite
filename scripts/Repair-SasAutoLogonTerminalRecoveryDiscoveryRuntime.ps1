#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$EvidenceRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasLocalSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Assert-SasPowerShellParses {
    param([Parameter(Mandatory = $true)][string]$Path)
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -ne 0) { throw "PowerShell parser rejected repaired recovery discovery runtime: $($errors[0].Message)" }
}

$runtimeRootFull = [IO.Path]::GetFullPath($RuntimeRoot)
$discoveryPath = Join-Path -Path $runtimeRootFull -ChildPath 'scripts\Recover-SasLatestInterruptedAutoLogonS4U.ps1'
if (-not (Test-Path -LiteralPath $discoveryPath -PathType Leaf)) { throw "AutoLogon recovery discovery runtime is missing: $discoveryPath" }

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $localRoot = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
    $EvidenceRoot = Join-Path -Path $localRoot -ChildPath 'SysAdminSuite\field-hotfixes'
}
$runId = 'terminal-recovery-discovery-repair-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
$runRoot = Join-Path -Path ([IO.Path]::GetFullPath($EvidenceRoot)) -ChildPath $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$evidencePath = Join-Path -Path $runRoot -ChildPath 'terminal-recovery-discovery-runtime-repair-result.json'
$backupPath = Join-Path -Path $runRoot -ChildPath 'Recover-SasLatestInterruptedAutoLogonS4U.ps1.before'

$record = [ordered]@{
    schema_version = 'sas-autologon-terminal-recovery-discovery-runtime-repair/v1'
    run_id = $runId
    status = 'STARTED'
    runtime_root = $runtimeRootFull
    target_file = $discoveryPath
    backup_path = $backupPath
    evidence_path = $evidencePath
    changed = $false
    already_applied = $false
    parser_valid = $false
    semantic_verification_passed = $false
    original_sha256 = $null
    repaired_sha256 = $null
    git_activity = 'NONE'
    network_activity = 'NONE'
    target_contact = 'NONE'
    target_mutation = 'NONE'
    error = $null
    completed_utc = $null
}

$terminalSkipAnchor = @'
        if (Test-Path -LiteralPath $terminal -PathType Leaf) { continue }
'@
$terminalReplacement = @'
        $terminalPilotPresent = Test-Path -LiteralPath $terminal -PathType Leaf
        $terminalPilotClassification = ''
        $terminalPilotRecoveryEligible = $false
        $terminalPilotParseFailed = $false
        if ($terminalPilotPresent) {
            try {
                $terminalPilot = Get-Content -LiteralPath $terminal -Raw -Encoding UTF8 | ConvertFrom-Json
                $terminalPilotClassification = Get-SasOptionalJsonString -Object $terminalPilot -Name 'classification'
            }
            catch {
                $terminalPilotParseFailed = $true
            }

            if (-not $terminalPilotParseFailed) {
                $terminalPilotRecoveryEligible = $terminalPilotClassification -in @(
                    'S4U_PROBE_CREATE_TIMEOUT',
                    'S4U_PROBE_CREATE_TIMEOUT_CONFIRMED_ABSENT',
                    'S4U_PROBE_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED'
                )
                if (-not $terminalPilotRecoveryEligible) { continue }
            }
        }
'@

$candidateAnchor = @'
            install_or_after_evidence_present=$installPresent
            last_write_utc=$file.LastWriteTimeUtc
'@
$candidateReplacement = @'
            install_or_after_evidence_present=$installPresent
            terminal_pilot_present=$terminalPilotPresent
            terminal_pilot_classification=$terminalPilotClassification
            terminal_pilot_recovery_eligible=$terminalPilotRecoveryEligible
            terminal_pilot_parse_failed=$terminalPilotParseFailed
            last_write_utc=$file.LastWriteTimeUtc
'@

$gateAnchor = @'
$candidates = @(Get-SasInterruptedS4UCandidates)
$unsafe = @($candidates | Where-Object { $_.install_or_after_evidence_present })
'@
$gateReplacement = @'
$candidates = @(Get-SasInterruptedS4UCandidates)
$unreadableTerminal = @($candidates | Where-Object { $_.terminal_pilot_parse_failed })
if ($unreadableTerminal.Count -gt 0) {
    $paths = @($unreadableTerminal | ForEach-Object { $_.local_s4u_root }) -join '; '
    throw "Interrupted AutoLogon terminal evidence is unreadable. Refusing target contact or automatic recovery. Review: $paths"
}

$unsafe = @($candidates | Where-Object { $_.install_or_after_evidence_present })
'@

try {
    $original = [IO.File]::ReadAllText($discoveryPath)
    $record.original_sha256 = Get-SasLocalSha256 -Path $discoveryPath
    Copy-Item -LiteralPath $discoveryPath -Destination $backupPath -Force

    $hasMarker = $original.Contains('terminal_pilot_recovery_eligible=$terminalPilotRecoveryEligible')
    $hasOldSkip = $original.Contains('if (Test-Path -LiteralPath $terminal -PathType Leaf) { continue }')
    $hasV3 = $original.Contains('sas-autologon-s4u-recovery-discovery/v3')
    if ($hasMarker -and -not $hasOldSkip -and $hasV3) {
        Assert-SasPowerShellParses -Path $discoveryPath
        $record.already_applied = $true
        $record.parser_valid = $true
        $record.semantic_verification_passed = $true
        $record.repaired_sha256 = $record.original_sha256
        $record.status = 'PASS_ALREADY_APPLIED'
    }
    else {
        if ($hasMarker -or -not $hasOldSkip -or $hasV3) { throw 'Recovery discovery runtime is neither the expected pre-repair form nor the completed repair form.' }

        $lineEnding = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
        $normalized = $original.Replace("`r`n", "`n")
        $tsa = $terminalSkipAnchor.Replace("`r`n", "`n")
        $tr = $terminalReplacement.Replace("`r`n", "`n")
        $ca = $candidateAnchor.Replace("`r`n", "`n")
        $cr = $candidateReplacement.Replace("`r`n", "`n")
        $ga = $gateAnchor.Replace("`r`n", "`n")
        $gr = $gateReplacement.Replace("`r`n", "`n")

        foreach ($entry in @(
            [pscustomobject]@{ Name='terminal skip'; Anchor=$tsa },
            [pscustomobject]@{ Name='candidate fields'; Anchor=$ca },
            [pscustomobject]@{ Name='pre-contact gate'; Anchor=$ga }
        )) {
            if (-not $normalized.Contains($entry.Anchor) -or $normalized.IndexOf($entry.Anchor) -ne $normalized.LastIndexOf($entry.Anchor)) {
                throw "$($entry.Name) anchor missing or ambiguous; refusing repair."
            }
        }

        $schemaV2 = 'sas-autologon-s4u-recovery-discovery/v2'
        $schemaCount = ([regex]::Matches($normalized, [regex]::Escape($schemaV2))).Count
        if ($schemaCount -ne 2) { throw "Expected exactly two recovery-discovery v2 schema markers; found $schemaCount." }

        $repairedNormalized = $normalized.Replace($tsa,$tr).Replace($ca,$cr).Replace($ga,$gr).Replace($schemaV2,'sas-autologon-s4u-recovery-discovery/v3')
        $repaired = if ($lineEnding -eq "`r`n") { $repairedNormalized.Replace("`n", "`r`n") } else { $repairedNormalized }
        [IO.File]::WriteAllText($discoveryPath, $repaired, (New-Object Text.UTF8Encoding($false)))
        Assert-SasPowerShellParses -Path $discoveryPath

        $verify = [IO.File]::ReadAllText($discoveryPath)
        foreach ($marker in @(
            'S4U_PROBE_CREATE_TIMEOUT_CONFIRMED_ABSENT',
            'S4U_PROBE_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED',
            'terminal_pilot_recovery_eligible=$terminalPilotRecoveryEligible',
            'terminal_pilot_parse_failed=$terminalPilotParseFailed',
            'Refusing target contact or automatic recovery',
            'sas-autologon-s4u-recovery-discovery/v3'
        )) {
            if (-not $verify.Contains($marker)) { throw "Semantic verification failed; marker missing: $marker" }
        }
        if ($verify.Contains('if (Test-Path -LiteralPath $terminal -PathType Leaf) { continue }')) {
            throw 'Semantic verification failed; old terminal-result skip remains.'
        }
        if ($verify.Contains('sas-autologon-s4u-recovery-discovery/v2')) {
            throw 'Semantic verification failed; old discovery schema remains.'
        }

        $record.changed = $true
        $record.parser_valid = $true
        $record.semantic_verification_passed = $true
        $record.repaired_sha256 = Get-SasLocalSha256 -Path $discoveryPath
        $record.status = 'PASS_REPAIRED'
    }
}
catch {
    $record.error = $_.Exception.Message
    $record.status = 'FAILED_RESTORED'
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) { Copy-Item -LiteralPath $backupPath -Destination $discoveryPath -Force }
    throw
}
finally {
    $record.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
    [pscustomobject]$record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
    Write-Host "Repair evidence: $evidencePath"
}

Write-Host 'PASS: TERMINAL PROBE-TIMEOUT RECOVERY DISCOVERY RUNTIME REPAIR APPLIED AND SEMANTICALLY VERIFIED' -ForegroundColor Green
Write-Host 'Git activity during repair: NONE'
Write-Host 'Network activity during repair: NONE'
Write-Host 'Target contact during repair: NONE'
Write-Host 'Target mutation during repair: NONE'
