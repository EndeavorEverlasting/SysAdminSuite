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
    if (@($errors).Count -ne 0) { throw "PowerShell parser rejected repaired recovery runtime: $($errors[0].Message)" }
}

$runtimeRootFull = [IO.Path]::GetFullPath($RuntimeRoot)
$recoveryPath = Join-Path -Path $runtimeRootFull -ChildPath 'scripts\Complete-SasInterruptedAutoLogonS4URecovery.ps1'
if (-not (Test-Path -LiteralPath $recoveryPath -PathType Leaf)) { throw "AutoLogon S4U recovery runtime is missing: $recoveryPath" }

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $localRoot = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
    $EvidenceRoot = Join-Path -Path $localRoot -ChildPath 'SysAdminSuite\field-hotfixes'
}
$runId = 'terminal-probe-recovery-repair-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
$runRoot = Join-Path -Path ([IO.Path]::GetFullPath($EvidenceRoot)) -ChildPath $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$evidencePath = Join-Path -Path $runRoot -ChildPath 'terminal-probe-recovery-runtime-repair-result.json'
$backupPath = Join-Path -Path $runRoot -ChildPath 'Complete-SasInterruptedAutoLogonS4URecovery.ps1.before'

$record = [ordered]@{
    schema_version = 'sas-autologon-terminal-probe-recovery-runtime-repair/v1'
    run_id = $runId
    status = 'STARTED'
    runtime_root = $runtimeRootFull
    target_file = $recoveryPath
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

$guardAnchor = @'
if (Test-Path -LiteralPath $terminalResult -PathType Leaf) { throw 'A terminal S4U pilot result already exists; use that result instead of interrupted recovery.' }
'@
$guardReplacement = @'
$terminalPilotPresent = Test-Path -LiteralPath $terminalResult -PathType Leaf
$terminalPilotClassification = $null
$terminalPilotRecoveryEligible = $false
if ($terminalPilotPresent) {
    try { $terminalPilot = Get-Content -LiteralPath $terminalResult -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Terminal S4U pilot result cannot be parsed; refusing recovery: $($_.Exception.Message)" }

    $terminalPilotClassification = [string]$terminalPilot.classification
    $allowedTerminalClassifications = @(
        'S4U_PROBE_CREATE_TIMEOUT',
        'S4U_PROBE_CREATE_TIMEOUT_CONFIRMED_ABSENT',
        'S4U_PROBE_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED'
    )
    if ($terminalPilotClassification -notin $allowedTerminalClassifications) {
        throw "Terminal S4U pilot classification is not probe-create-timeout recovery eligible: $terminalPilotClassification"
    }

    if ($null -eq $terminalPilot.probe) { throw 'Terminal S4U pilot result does not contain recorded probe lifecycle identity.' }
    $terminalProbeTaskName = [string]$terminalPilot.probe.task_name
    if ([string]::IsNullOrWhiteSpace($terminalProbeTaskName) -or
        -not $terminalProbeTaskName.Equals($TaskName, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Terminal S4U pilot probe task identity does not match requested recovery task: $TaskName"
    }
    if ($null -ne $terminalPilot.install) { throw 'Terminal S4U pilot result contains installer lifecycle evidence; refusing probe-only recovery.' }
    if ($null -ne $terminalPilot.installer_exit_code) { throw 'Terminal S4U pilot result contains an installer exit code; refusing probe-only recovery.' }
    if ([bool]$terminalPilot.pre_reboot_autologon_ready) { throw 'Terminal S4U pilot result reports pre-reboot AutoLogon ready; refusing probe-only recovery.' }
    if ([bool]$terminalPilot.automatic_reboot_performed) { throw 'Terminal S4U pilot result reports automatic reboot; refusing probe-only recovery.' }
    if (-not [string]::IsNullOrWhiteSpace([string]$terminalPilot.after_snapshot_path)) { throw 'Terminal S4U pilot result references after-state evidence; refusing probe-only recovery.' }

    $terminalPilotRecoveryEligible = $true
    Write-Host "Terminal probe-timeout result accepted for exact recovery: $terminalPilotClassification" -ForegroundColor Green
}
'@

$resultAnchor = @'
    schema_version = 'sas-autologon-s4u-interrupted-recovery/v2'
'@
$resultReplacement = @'
    schema_version = 'sas-autologon-s4u-interrupted-recovery/v3'
'@

$terminalFieldAnchor = @'
    terminal_pilot_result_present = $false
    installer_phase_entered = $false
'@
$terminalFieldReplacement = @'
    terminal_pilot_result_present = $terminalPilotPresent
    terminal_pilot_classification = $terminalPilotClassification
    terminal_pilot_recovery_eligible = $terminalPilotRecoveryEligible
    installer_phase_entered = $false
'@

try {
    $original = [IO.File]::ReadAllText($recoveryPath)
    $record.original_sha256 = Get-SasLocalSha256 -Path $recoveryPath
    Copy-Item -LiteralPath $recoveryPath -Destination $backupPath -Force

    $hasMarker = $original.Contains('terminal_pilot_recovery_eligible = $terminalPilotRecoveryEligible')
    $hasOldGuard = $original.Contains('A terminal S4U pilot result already exists; use that result instead of interrupted recovery.')
    if ($hasMarker -and -not $hasOldGuard) {
        Assert-SasPowerShellParses -Path $recoveryPath
        $record.already_applied = $true
        $record.parser_valid = $true
        $record.semantic_verification_passed = $true
        $record.repaired_sha256 = $record.original_sha256
        $record.status = 'PASS_ALREADY_APPLIED'
    }
    else {
        if ($hasMarker -or -not $hasOldGuard) { throw 'Recovery runtime is neither the expected pre-repair form nor the completed repair form.' }

        $lineEnding = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
        $normalized = $original.Replace("`r`n", "`n")
        $ga = $guardAnchor.Replace("`r`n", "`n")
        $gr = $guardReplacement.Replace("`r`n", "`n")
        $ra = $resultAnchor.Replace("`r`n", "`n")
        $rr = $resultReplacement.Replace("`r`n", "`n")
        $ta = $terminalFieldAnchor.Replace("`r`n", "`n")
        $tr = $terminalFieldReplacement.Replace("`r`n", "`n")

        foreach ($entry in @(
            [pscustomobject]@{ Name='terminal guard'; Anchor=$ga },
            [pscustomobject]@{ Name='result schema'; Anchor=$ra },
            [pscustomobject]@{ Name='terminal result fields'; Anchor=$ta }
        )) {
            if (-not $normalized.Contains($entry.Anchor) -or $normalized.IndexOf($entry.Anchor) -ne $normalized.LastIndexOf($entry.Anchor)) {
                throw "$($entry.Name) anchor missing or ambiguous; refusing repair."
            }
        }

        $repairedNormalized = $normalized.Replace($ga,$gr).Replace($ra,$rr).Replace($ta,$tr)
        $repaired = if ($lineEnding -eq "`r`n") { $repairedNormalized.Replace("`n", "`r`n") } else { $repairedNormalized }
        [IO.File]::WriteAllText($recoveryPath, $repaired, (New-Object Text.UTF8Encoding($false)))
        Assert-SasPowerShellParses -Path $recoveryPath

        $verify = [IO.File]::ReadAllText($recoveryPath)
        foreach ($marker in @(
            'S4U_PROBE_CREATE_TIMEOUT_CONFIRMED_ABSENT',
            'S4U_PROBE_CREATE_TIMEOUT_CONFIRMATION_UNVERIFIED',
            'Terminal S4U pilot probe task identity does not match requested recovery task',
            'terminal_pilot_recovery_eligible = $terminalPilotRecoveryEligible',
            "schema_version = 'sas-autologon-s4u-interrupted-recovery/v3'"
        )) {
            if (-not $verify.Contains($marker)) { throw "Semantic verification failed; marker missing: $marker" }
        }
        if ($verify.Contains('A terminal S4U pilot result already exists; use that result instead of interrupted recovery.')) {
            throw 'Semantic verification failed; old terminal-result refusal remains.'
        }

        $record.changed = $true
        $record.parser_valid = $true
        $record.semantic_verification_passed = $true
        $record.repaired_sha256 = Get-SasLocalSha256 -Path $recoveryPath
        $record.status = 'PASS_REPAIRED'
    }
}
catch {
    $record.error = $_.Exception.Message
    $record.status = 'FAILED_RESTORED'
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) { Copy-Item -LiteralPath $backupPath -Destination $recoveryPath -Force }
    throw
}
finally {
    $record.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
    [pscustomobject]$record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
    Write-Host "Repair evidence: $evidencePath"
}

Write-Host 'PASS: TERMINAL PROBE-TIMEOUT RECOVERY RUNTIME REPAIR APPLIED AND SEMANTICALLY VERIFIED' -ForegroundColor Green
Write-Host 'Git activity during repair: NONE'
Write-Host 'Network activity during repair: NONE'
Write-Host 'Target contact during repair: NONE'
Write-Host 'Target mutation during repair: NONE'
