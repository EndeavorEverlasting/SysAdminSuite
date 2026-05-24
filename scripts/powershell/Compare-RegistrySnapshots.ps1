<#
.SYNOPSIS
Compares two registry snapshot JSON files and classifies before/after changes.

.DESCRIPTION
Compare-RegistrySnapshots.ps1 performs offline evidence comparison between two previously
captured registry snapshots. It does not query the registry, run installers, or modify system state.

The script normalizes registry key/value identities, computes Created/Deleted/Modified key/value
changes, applies optional rule classifications (expected/noise/suspicious/remediation candidate),
and emits a structured diff object. JSON and CSV outputs are optional.

.PARAMETER BeforeSnapshotPath
Path to the pre-install registry snapshot JSON.

.PARAMETER AfterSnapshotPath
Path to the post-install registry snapshot JSON.

.PARAMETER SoftwareId
Optional software identifier (for example EXAMPLE-SOFTWARE-ID) included in output metadata.

.PARAMETER ExpectedRulesPath
Optional JSON path containing expected-change rule sections.

.PARAMETER WatchlistPath
Optional JSON path containing noise/suspicious/remediation rule sections.

.PARAMETER OutputJson
Optional output path for structured JSON diff results.

.PARAMETER OutputCsv
Optional output path for flattened CSV changes.

.EXAMPLE
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/Compare-RegistrySnapshots.ps1 `
  -BeforeSnapshotPath .\before.json -AfterSnapshotPath .\after.json

Compare two snapshot files and print structured JSON to stdout.

.EXAMPLE
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/Compare-RegistrySnapshots.ps1 `
  -BeforeSnapshotPath .\before.json -AfterSnapshotPath .\after.json -SoftwareId EXAMPLE-SOFTWARE-ID

Compare two snapshot files and stamp the software id in evidence output.

.EXAMPLE
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/Compare-RegistrySnapshots.ps1 `
  -BeforeSnapshotPath .\before.json -AfterSnapshotPath .\after.json `
  -ExpectedRulesPath .\config\expected_rules.json -WatchlistPath .\config\watchlist.json

Compare with rules for expected/noise/suspicious/remediation classification.

.EXAMPLE
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/Compare-RegistrySnapshots.ps1 `
  -BeforeSnapshotPath .\before.json -AfterSnapshotPath .\after.json `
  -OutputJson .\registry_diff.json -OutputCsv .\registry_diff.csv

Compare snapshots and write both JSON and CSV outputs.

.NOTES
Safety: read-only evidence diff only. This script does not read live registry state,
does not apply registry edits, and does not execute installers.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BeforeSnapshotPath,

    [Parameter(Mandatory = $true)]
    [string]$AfterSnapshotPath,

    [Parameter(Mandatory = $false)]
    [string]$SoftwareId,

    [Parameter(Mandatory = $false)]
    [string]$ExpectedRulesPath,

    [Parameter(Mandatory = $false)]
    [string]$WatchlistPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputJson,

    [Parameter(Mandatory = $false)]
    [string]$OutputCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$KeySentinelName = '__REGISTRY_KEY_ONLY__'

function Normalize-KeyPath {
    param([string]$KeyPath)
    if ([string]::IsNullOrWhiteSpace($KeyPath)) { return '' }
    $normalized = $KeyPath -replace '/', '\\'
    $normalized = $normalized.Trim()
    while ($normalized.EndsWith('\\')) { $normalized = $normalized.Substring(0, $normalized.Length - 1) }
    return $normalized.ToLowerInvariant()
}

function Normalize-ValueName {
    param([string]$ValueName)
    if ([string]::IsNullOrWhiteSpace($ValueName)) { return '(default)' }
    return $ValueName.Trim().ToLowerInvariant()
}

function New-ValueState {
    param($Item)
    [pscustomobject]@{
        value_type      = if ($null -ne $Item.value_type) { [string]$Item.value_type } else { $null }
        value_data      = if ($null -ne $Item.value_data) { $Item.value_data } else { $null }
        value_data_kind = if ($null -ne $Item.value_data_kind) { [string]$Item.value_data_kind } else { $null }
        access_status   = if ($null -ne $Item.access_status) { [string]$Item.access_status } else { $null }
    }
}

function Read-JsonFile {
    param([string]$Path, [ref]$Errors)
    if (-not $Path) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) {
        $Errors.Value += "File not found: $Path"
        return $null
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 50)
    }
    catch {
        $Errors.Value += "Failed to parse JSON file '$Path': $($_.Exception.Message)"
        return $null
    }
}

function Get-SnapshotEntries {
    param($Snapshot)
    if ($null -eq $Snapshot) { return @() }

    if ($Snapshot -is [array]) { return $Snapshot }

    foreach ($candidate in @('entries', 'items', 'snapshot_entries', 'data')) {
        if ($null -ne $Snapshot.$candidate) {
            if ($Snapshot.$candidate -is [array]) { return $Snapshot.$candidate }
            return @($Snapshot.$candidate)
        }
    }

    return @()
}

function Test-RuleMatch {
    param($Change, $Rule)

    $match = $true

    if ($Rule.software_id -and $SoftwareId) {
        if ([string]$Rule.software_id -ne [string]$SoftwareId) { $match = $false }
    }

    if ($match -and $Rule.classification -and [string]$Rule.classification -ne [string]$Change.classification) {
        $match = $false
    }

    if ($match -and $Rule.key_path_regex) {
        if (-not ([string]$Change.key_path -match [string]$Rule.key_path_regex)) { $match = $false }
    }

    if ($match -and $Rule.value_name_regex) {
        if (-not ([string]$Change.value_name -match [string]$Rule.value_name_regex)) { $match = $false }
    }

    if ($match -and $Rule.reason_contains) {
        if (-not ([string]$Change.reason -like "*$($Rule.reason_contains)*")) { $match = $false }
    }

    return $match
}

function Get-RuleSection {
    param($RuleDoc, [string]$PrimaryName, [string]$AliasName)
    if ($null -eq $RuleDoc) { return @() }
    if ($null -ne $RuleDoc.$PrimaryName) { return @($RuleDoc.$PrimaryName) }
    if ($AliasName -and $null -ne $RuleDoc.$AliasName) { return @($RuleDoc.$AliasName) }
    return @()
}

$errors = @()
$beforeSnapshot = Read-JsonFile -Path $BeforeSnapshotPath -Errors ([ref]$errors)
$afterSnapshot = Read-JsonFile -Path $AfterSnapshotPath -Errors ([ref]$errors)
$expectedDoc = Read-JsonFile -Path $ExpectedRulesPath -Errors ([ref]$errors)
$watchlistDoc = Read-JsonFile -Path $WatchlistPath -Errors ([ref]$errors)

$beforeEntries = Get-SnapshotEntries -Snapshot $beforeSnapshot
$afterEntries = Get-SnapshotEntries -Snapshot $afterSnapshot

$beforeMap = @{}
$afterMap = @{}

foreach ($item in $beforeEntries) {
    $keyPath = if ($null -ne $item.key_path) { [string]$item.key_path } elseif ($null -ne $item.path) { [string]$item.path } else { '' }
    $valueName = if ($null -ne $item.value_name) { [string]$item.value_name } elseif ($null -ne $item.name) { [string]$item.name } else { $KeySentinelName }

    $normKey = Normalize-KeyPath -KeyPath $keyPath
    $normValue = if ($valueName -eq $KeySentinelName) { $KeySentinelName } else { Normalize-ValueName -ValueName $valueName }
    $identity = "$normKey|$normValue"

    $beforeMap[$identity] = [pscustomobject]@{
        key_path           = $keyPath
        value_name         = $valueName
        normalized_key     = $normKey
        normalized_name    = $normValue
        is_key_only        = ($valueName -eq $KeySentinelName)
        state              = New-ValueState -Item $item
    }
}

foreach ($item in $afterEntries) {
    $keyPath = if ($null -ne $item.key_path) { [string]$item.key_path } elseif ($null -ne $item.path) { [string]$item.path } else { '' }
    $valueName = if ($null -ne $item.value_name) { [string]$item.value_name } elseif ($null -ne $item.name) { [string]$item.name } else { $KeySentinelName }

    $normKey = Normalize-KeyPath -KeyPath $keyPath
    $normValue = if ($valueName -eq $KeySentinelName) { $KeySentinelName } else { Normalize-ValueName -ValueName $valueName }
    $identity = "$normKey|$normValue"

    $afterMap[$identity] = [pscustomobject]@{
        key_path           = $keyPath
        value_name         = $valueName
        normalized_key     = $normKey
        normalized_name    = $normValue
        is_key_only        = ($valueName -eq $KeySentinelName)
        state              = New-ValueState -Item $item
    }
}

$allIds = @($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)
$changes = @()

foreach ($id in $allIds) {
    $before = if ($beforeMap.ContainsKey($id)) { $beforeMap[$id] } else { $null }
    $after = if ($afterMap.ContainsKey($id)) { $afterMap[$id] } else { $null }

    $baseClassification = $null
    $reason = $null

    if ($null -eq $before -and $null -ne $after) {
        if ($after.is_key_only) {
            $baseClassification = 'CreatedKey'
            $reason = 'Registry key exists after snapshot only.'
        } else {
            $baseClassification = 'CreatedValue'
            $reason = 'Registry value exists after snapshot only.'
        }
    }
    elseif ($null -ne $before -and $null -eq $after) {
        if ($before.is_key_only) {
            $baseClassification = 'DeletedKey'
            $reason = 'Registry key exists before snapshot only.'
        } else {
            $baseClassification = 'DeletedValue'
            $reason = 'Registry value exists before snapshot only.'
        }
    }
    elseif ($null -ne $before -and $null -ne $after -and -not $before.is_key_only -and -not $after.is_key_only) {
        $isModified = $false
        if ($before.state.value_type -ne $after.state.value_type) { $isModified = $true }
        elseif (($before.state.value_data | ConvertTo-Json -Depth 20 -Compress) -ne ($after.state.value_data | ConvertTo-Json -Depth 20 -Compress)) { $isModified = $true }
        elseif ($before.state.value_data_kind -ne $after.state.value_data_kind) { $isModified = $true }
        elseif ($before.state.access_status -ne $after.state.access_status) { $isModified = $true }

        if ($isModified) {
            $baseClassification = 'ModifiedValue'
            $reason = 'Value data, type, data kind, or access status changed.'
        }
    }

    if (-not $baseClassification) { continue }

    $change = [pscustomobject]@{
        base_classification = $baseClassification
        classification      = $baseClassification
        key_path            = if ($null -ne $after) { $after.key_path } else { $before.key_path }
        value_name          = if ($null -ne $after) { $after.value_name } else { $before.value_name }
        before              = if ($null -ne $before) { $before.state } else { $null }
        after               = if ($null -ne $after) { $after.state } else { $null }
        reason              = $reason
        evidence            = [pscustomobject]@{ identity = $id }
        confidence          = 'medium'
        matched_rule_id     = $null
        requires_review     = $true
    }

    $changes += $change
}

$expectedRules = @((Get-RuleSection -RuleDoc $expectedDoc -PrimaryName 'expected_change_rules' -AliasName 'expected_rules'))
$noiseRules = @((Get-RuleSection -RuleDoc $watchlistDoc -PrimaryName 'noise_patterns' -AliasName 'noise_rules'))
$suspiciousRules = @((Get-RuleSection -RuleDoc $watchlistDoc -PrimaryName 'suspicious_change_rules' -AliasName 'suspicious_rules'))
$remediationRules = @((Get-RuleSection -RuleDoc $watchlistDoc -PrimaryName 'remediation_candidate_rules' -AliasName 'remediation_rules'))

foreach ($change in $changes) {
    $matched = $false

    foreach ($rule in $noiseRules) {
        if (Test-RuleMatch -Change $change -Rule $rule) {
            $change.classification = 'Noise'
            $change.reason = if ($rule.reason) { [string]$rule.reason } else { 'Matched noise pattern.' }
            $change.matched_rule_id = if ($rule.id) { [string]$rule.id } else { 'noise-rule' }
            $change.confidence = if ($rule.confidence) { [string]$rule.confidence } else { 'high' }
            $change.requires_review = $false
            $matched = $true
            break
        }
    }

    if ($matched) { continue }

    foreach ($rule in $expectedRules) {
        if (Test-RuleMatch -Change $change -Rule $rule) {
            $change.classification = 'ExpectedChange'
            $change.reason = if ($rule.reason) { [string]$rule.reason } else { 'Matched expected change rule.' }
            $change.matched_rule_id = if ($rule.id) { [string]$rule.id } else { 'expected-rule' }
            $change.confidence = if ($rule.confidence) { [string]$rule.confidence } else { 'high' }
            $change.requires_review = $false
            $matched = $true
            break
        }
    }

    if ($matched) { continue }

    foreach ($rule in $remediationRules) {
        if (Test-RuleMatch -Change $change -Rule $rule) {
            $change.classification = 'RemediationCandidate'
            $change.reason = if ($rule.reason) { [string]$rule.reason } else { 'Matched remediation candidate rule.' }
            $change.matched_rule_id = if ($rule.id) { [string]$rule.id } else { 'remediation-rule' }
            $change.confidence = if ($rule.confidence) { [string]$rule.confidence } else { 'medium' }
            $change.requires_review = $true
            $matched = $true
            break
        }
    }

    if ($matched) { continue }

    foreach ($rule in $suspiciousRules) {
        if (Test-RuleMatch -Change $change -Rule $rule) {
            $change.classification = 'SuspiciousChange'
            $change.reason = if ($rule.reason) { [string]$rule.reason } else { 'Matched suspicious change rule.' }
            $change.matched_rule_id = if ($rule.id) { [string]$rule.id } else { 'suspicious-rule' }
            $change.confidence = if ($rule.confidence) { [string]$rule.confidence } else { 'medium' }
            $change.requires_review = $true
            break
        }
    }
}

$result = [pscustomobject]@{
    schema_version = '1.0.0'
    run_id         = [guid]::NewGuid().ToString()
    target         = if ($afterSnapshot.target) { [string]$afterSnapshot.target } elseif ($beforeSnapshot.target) { [string]$beforeSnapshot.target } else { 'unknown' }
    software_id    = if ($SoftwareId) { $SoftwareId } else { $null }
    compared_at    = (Get-Date).ToString('o')
    before_snapshot = [pscustomobject]@{ path = $BeforeSnapshotPath; entries = $beforeEntries.Count }
    after_snapshot  = [pscustomobject]@{ path = $AfterSnapshotPath; entries = $afterEntries.Count }
    summary = [pscustomobject]@{
        total_changes          = $changes.Count
        created_keys           = @($changes | Where-Object { $_.base_classification -eq 'CreatedKey' }).Count
        deleted_keys           = @($changes | Where-Object { $_.base_classification -eq 'DeletedKey' }).Count
        created_values         = @($changes | Where-Object { $_.base_classification -eq 'CreatedValue' }).Count
        deleted_values         = @($changes | Where-Object { $_.base_classification -eq 'DeletedValue' }).Count
        modified_values        = @($changes | Where-Object { $_.base_classification -eq 'ModifiedValue' }).Count
        expected_changes       = @($changes | Where-Object { $_.classification -eq 'ExpectedChange' }).Count
        noise_changes          = @($changes | Where-Object { $_.classification -eq 'Noise' }).Count
        suspicious_changes     = @($changes | Where-Object { $_.classification -eq 'SuspiciousChange' }).Count
        remediation_candidates = @($changes | Where-Object { $_.classification -eq 'RemediationCandidate' }).Count
        requires_review_count  = @($changes | Where-Object { $_.requires_review -eq $true }).Count
    }
    changes = $changes
    errors  = $errors
    output_paths = [pscustomobject]@{
        json = $OutputJson
        csv  = $OutputCsv
    }
}

if ($OutputJson) {
    ($result | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $OutputJson -Encoding UTF8
}

if ($OutputCsv) {
    $changes | Select-Object classification, base_classification, key_path, value_name, reason, confidence, matched_rule_id, requires_review,
    @{ Name = 'before_value_type'; Expression = { if ($_.before) { $_.before.value_type } else { $null } } },
    @{ Name = 'before_value_data'; Expression = { if ($_.before) { ($_.before.value_data | ConvertTo-Json -Compress -Depth 10) } else { $null } } },
    @{ Name = 'after_value_type'; Expression = { if ($_.after) { $_.after.value_type } else { $null } } },
    @{ Name = 'after_value_data'; Expression = { if ($_.after) { ($_.after.value_data | ConvertTo-Json -Compress -Depth 10) } else { $null } } } |
    Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
}

$result | ConvertTo-Json -Depth 20
