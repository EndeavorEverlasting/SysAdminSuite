#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\SASAL',
    [string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][switch]$ConfirmRepair,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (-not $ConfirmRepair) { throw 'S4U create-timeout runtime repair requires -ConfirmRepair.' }

$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$targetPath = Join-Path $RuntimeRoot 'scripts\SasBoundedNative.psm1'
if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    throw "Bounded-native runtime surface missing: $targetPath"
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $base = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $RuntimeRoot 'runs\field-repair'
    } else {
        Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-hotfixes'
    }
    $EvidenceRoot = Join-Path $base ('s4u-create-timeout-repair-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$backupPath = Join-Path $EvidenceRoot 'SasBoundedNative.before.psm1'
$resultPath = Join-Path $EvidenceRoot 's4u-create-timeout-runtime-repair-result.json'

function Get-RepairHash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Assert-Parse([string]$Text) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw ('Repaired bounded-native module does not parse: ' + (($errors | ForEach-Object { $_.Message }) -join '; '))
    }
}

function Test-RepairPresent([string]$Text) {
    $exactIdentityMarkers = ($Text.Contains("'^SysAdminSuite-AutoLogonS4U(?:Probe|Install)-[0-9a-fA-F]{32}$'") -and
        $Text.Contains("'/Query','/S',`$s4uCreateTarget,'/TN',`$s4uCreateTaskName"))
    if (-not $exactIdentityMarkers) { return $false }

    # Fresh runtimes carry the repository-integrated one-shot policy: one 120-second create mutation
    # plus a finite exact read-only reconciliation window. Never wrap that implementation again.
    $newIntegratedLayout = ($Text.Contains('function Invoke-SasBoundedNative {') -and
        $Text.Contains("`$timeoutPolicy = 's4u_task_create_minimum_120'") -and
        $Text.Contains('$reconciliationAttemptLimit = 3') -and
        $Text.Contains('reconciliation_attempt_limit = $reconciliationAttemptLimit') -and
        $Text.Contains('reconciliation_attempts = @($reconciliationAttempts)'))

    # Compatibility: a previously sealed runtime may already contain the August 60-second direct
    # implementation or the local wrapper repair. This script remains idempotent for those layouts;
    # canonical upgrade to the new one-shot policy is performed by Guest/Internet `sas refresh`.
    $legacyIntegratedLayout = ($Text.Contains('function Invoke-SasBoundedNative {') -and
        $Text.Contains("`$timeoutPolicy = 's4u_task_create_minimum_60'") -and
        $Text.Contains('$result = Invoke-SasBoundedPowerShell -ScriptText $child -TimeoutSeconds $effectiveTimeoutSeconds') -and
        $Text.Contains('reconciled_after_timeout = $true'))
    $wrappedLegacyLayout = ($Text.Contains('function Invoke-SasBoundedNativeCore {') -and
        $Text.Contains("`$timeoutPolicy = 's4u_task_create_minimum_60'") -and
        $Text.Contains('NotePropertyName reconciled_after_timeout'))
    return ($newIntegratedLayout -or $legacyIntegratedLayout -or $wrappedLegacyLayout)
}

$source = [IO.File]::ReadAllText($targetPath)
$beforeSha = Get-RepairHash $targetPath
$changed = $false
$classification = 'AUTOLOGON_S4U_CREATE_TIMEOUT_RUNTIME_REPAIR_ALREADY_PRESENT'
$repairStrategy = 'already_integrated_or_wrapped'

if (-not (Test-RepairPresent $source)) {
    Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force -ErrorAction Stop
    $newline = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
    $text = $source.Replace("`r`n","`n").Replace("`r","`n")

    $oldFunctionMarker = 'function Invoke-SasBoundedNative {'
    $nextFunctionMarker = 'function Test-SasBoundedPath {'
    $oldFunctionIndex = $text.IndexOf($oldFunctionMarker, [StringComparison]::Ordinal)
    $nextFunctionIndex = $text.IndexOf($nextFunctionMarker, [StringComparison]::Ordinal)
    if ($oldFunctionIndex -lt 0 -or $nextFunctionIndex -le $oldFunctionIndex) {
        throw 'Bounded-native repair function boundaries were not found.'
    }
    if ($text.IndexOf($oldFunctionMarker, $oldFunctionIndex + 1, [StringComparison]::Ordinal) -ge 0 -or
        $text.IndexOf($nextFunctionMarker, $nextFunctionIndex + 1, [StringComparison]::Ordinal) -ge 0) {
        throw 'Bounded-native repair function boundaries are ambiguous.'
    }

    $text = $text.Remove($oldFunctionIndex, $oldFunctionMarker.Length).Insert(
        $oldFunctionIndex,
        'function Invoke-SasBoundedNativeCore {'
    )
    $nextFunctionIndex = $text.IndexOf($nextFunctionMarker, [StringComparison]::Ordinal)

    # Legacy local-only fallback retained for already-sealed older runtimes. The canonical field
    # path is refresh/reseal; this wrapper is deliberately not broadened into a second updater.
    $wrapper = @'
function Invoke-SasBoundedNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [ValidateRange(1,300)][int]$TimeoutSeconds = 30
    )

    $requestedTimeoutSeconds = $TimeoutSeconds
    $effectiveTimeoutSeconds = $TimeoutSeconds
    $timeoutPolicy = 'requested'
    $s4uCreateTarget = $null
    $s4uCreateTaskName = $null
    $isExactS4UCreate = $false

    if ([IO.Path]::GetFileName($FilePath).Equals('schtasks.exe', [StringComparison]::OrdinalIgnoreCase)) {
        $hasCreate = @($Arguments | Where-Object {
            ([string]$_).Equals('/Create', [StringComparison]::OrdinalIgnoreCase)
        }).Count -eq 1
        for ($i = 0; $i -lt $Arguments.Count - 1; $i++) {
            if (([string]$Arguments[$i]).Equals('/S', [StringComparison]::OrdinalIgnoreCase)) {
                $s4uCreateTarget = [string]$Arguments[$i + 1]
            }
            elseif (([string]$Arguments[$i]).Equals('/TN', [StringComparison]::OrdinalIgnoreCase)) {
                $s4uCreateTaskName = [string]$Arguments[$i + 1]
            }
        }
        $isExactS4UCreate = ($hasCreate -and
            -not [string]::IsNullOrWhiteSpace($s4uCreateTarget) -and
            [string]$s4uCreateTaskName -match '^SysAdminSuite-AutoLogonS4U(?:Probe|Install)-[0-9a-fA-F]{32}$')
    }

    if (-not $isExactS4UCreate) {
        return Invoke-SasBoundedNativeCore -FilePath $FilePath -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
    }

    if ($effectiveTimeoutSeconds -lt 60) {
        $effectiveTimeoutSeconds = 60
        $timeoutPolicy = 's4u_task_create_minimum_60'
    }

    $result = Invoke-SasBoundedNativeCore -FilePath $FilePath -Arguments $Arguments -TimeoutSeconds $effectiveTimeoutSeconds
    $initialTimedOut = [bool]$result.timed_out
    $reconciliation = $null
    $reconciledAfterTimeout = $false

    if ($initialTimedOut) {
        $reconciliation = Invoke-SasBoundedNativeCore -FilePath $FilePath -Arguments @(
            '/Query','/S',$s4uCreateTarget,'/TN',$s4uCreateTaskName
        ) -TimeoutSeconds $requestedTimeoutSeconds
        $reconciledAfterTimeout = (-not [bool]$reconciliation.timed_out -and [int]$reconciliation.exit_code -eq 0)
    }

    $result | Add-Member -NotePropertyName requested_timeout_seconds -NotePropertyValue $requestedTimeoutSeconds -Force
    $result | Add-Member -NotePropertyName timeout_policy -NotePropertyValue $timeoutPolicy -Force
    $result | Add-Member -NotePropertyName initial_timed_out -NotePropertyValue $initialTimedOut -Force
    $result | Add-Member -NotePropertyName reconciled_after_timeout -NotePropertyValue $reconciledAfterTimeout -Force
    $result | Add-Member -NotePropertyName reconciliation -NotePropertyValue $reconciliation -Force
    $result | Add-Member -NotePropertyName initial_error -NotePropertyValue $(if ($initialTimedOut) { [string]$result.error } else { $null }) -Force

    if ($reconciledAfterTimeout) {
        $result.exit_code = 0
        $result.timed_out = $false
        $result.output = [string]$reconciliation.output
        $result.error = ''
        $result.completed_utc = [string]$reconciliation.completed_utc
    }

    return $result
}

'@

    $candidate = $text.Insert($nextFunctionIndex, $wrapper)
    if ($newline -eq "`r`n") { $candidate = $candidate.Replace("`n","`r`n") }

    try {
        Assert-Parse $candidate
        if (-not (Test-RepairPresent $candidate)) {
            throw 'S4U create-timeout repair semantic verification failed.'
        }
        [IO.File]::WriteAllText($targetPath, $candidate, (New-Object Text.UTF8Encoding($false)))
        $changed = $true
        $classification = 'AUTOLOGON_S4U_CREATE_TIMEOUT_RUNTIME_REPAIR_APPLIED'
        $repairStrategy = 'rename_core_and_insert_wrapper'
    }
    catch {
        Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force -ErrorAction SilentlyContinue
        throw "S4U CREATE-TIMEOUT REPAIR FAILED; ORIGINAL RESTORED. $($_.Exception.Message)"
    }
}

$final = [IO.File]::ReadAllText($targetPath)
Assert-Parse $final
if (-not (Test-RepairPresent $final)) {
    throw 'S4U create-timeout repair markers are absent after repair.'
}
$afterSha = Get-RepairHash $targetPath
$isOneShotPolicy = ($final.Contains("`$timeoutPolicy = 's4u_task_create_minimum_120'") -and
    $final.Contains('$reconciliationAttemptLimit = 3'))
$result = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-s4u-create-timeout-runtime-repair/v3'
    classification = $classification
    runtime_root = $RuntimeRoot
    target_path = $targetPath
    changed = $changed
    before_sha256 = $beforeSha
    after_sha256 = $afterSha
    s4u_create_minimum_timeout_seconds = $(if ($isOneShotPolicy) { 120 } else { 60 })
    reconciliation_attempt_limit = $(if ($isOneShotPolicy) { 3 } else { 1 })
    exact_task_name_pattern = '^SysAdminSuite-AutoLogonS4U(?:Probe|Install)-[0-9a-fA-F]{32}$'
    exact_query_reconciliation = $true
    canonical_upgrade_path = 'sas refresh on Guest/Internet'
    repair_strategy = $repairStrategy
    powershell_parse_passed = $true
    semantic_verification = $true
    git_performed = $false
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
    evidence_path = $resultPath
    completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
if ($PassThru) { return $result }
Write-Host $result.classification -ForegroundColor Green
Write-Host "Evidence: $resultPath"
