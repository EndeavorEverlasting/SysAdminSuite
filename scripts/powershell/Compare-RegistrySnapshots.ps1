# Requires PowerShell 5.1+
<#
.SYNOPSIS
Compares two registry snapshot JSON files and classifies before/after changes.

.DESCRIPTION
Compare-RegistrySnapshots.ps1 performs offline evidence comparison between two previously
captured registry snapshots. It does not query live registry state, run installers, or modify
system state. It normalizes key/value identities, computes created/deleted/modified changes,
applies optional rule classifications, and emits structured JSON plus optional JSON/CSV files.

.PARAMETER BeforeSnapshotPath
Path to the pre-install registry snapshot JSON.

.PARAMETER AfterSnapshotPath
Path to the post-install registry snapshot JSON.

.PARAMETER SoftwareId
Optional software identifier included in output metadata.

.PARAMETER ExpectedRulesPath
Optional JSON path containing expected-change rule sections.

.PARAMETER WatchlistPath
Optional JSON path containing noise/suspicious/remediation rule sections.

.PARAMETER OutputJson
Optional output path for structured JSON diff results.

.PARAMETER OutputCsv
Optional output path for flattened CSV changes.

.EXAMPLE
powershell.exe -File scripts/powershell/Compare-RegistrySnapshots.ps1 -BeforeSnapshotPath .\before.json -AfterSnapshotPath .\after.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BeforeSnapshotPath,

    [Parameter(Mandatory = $true)]
    [string]$AfterSnapshotPath,

    [string]$SoftwareId,
    [string]$ExpectedRulesPath,
    [string]$WatchlistPath,
    [string]$OutputJson,
    [string]$OutputCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$KeySentinelName = '__REGISTRY_KEY_ONLY__'

function Get-ObjectPropertyValue {
    param($InputObject, [string]$Name, $Default = $null)
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Normalize-KeyPath {
    param([string]$KeyPath)
    if ([string]::IsNullOrWhiteSpace($KeyPath)) { return '' }
    $normalized = $KeyPath -replace '/', '\'
    $normalized = $normalized.Trim()
    while ($normalized.EndsWith('\')) { $normalized = $normalized.Substring(0, $normalized.Length - 1) }
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
        value_type      = Get-ObjectPropertyValue -InputObject $Item -Name 'value_type'
        value_data      = Get-ObjectPropertyValue -InputObject $Item -Name 'value_data'
        value_data_kind = Get-ObjectPropertyValue -InputObject $Item -Name 'value_data_kind'
        access_status   = Get-ObjectPropertyValue -InputObject $Item -Name 'access_status'
    }
}

function Read-JsonFile {
    param([string]$Path, [ref]$Errors)
    if (-not $Path) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) {
        $Errors.Value += "File not found: $Path"
        return $null
    }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
    catch {
        $Errors.Value += "Failed to parse JSON file '$Path': $($_.Exception.Message)"
        return $null
    }
}

function Get-SnapshotEntries {
    param($Snapshot)
    if ($null -eq $Snapshot) { return @() }
    if ($Snapshot -is [array]) { return @($Snapshot) }
    foreach ($candidate in @('entries', 'items', 'snapshot_entries', 'data')) {
        $property = $Snapshot.PSObject.Properties[$candidate]
        if ($null -ne $property) { return @($property.Value) }
    }
    return @()
}

function Get-RuleSection {
    param($RuleDoc, [string]$PrimaryName, [string]$AliasName)
    if ($null -eq $RuleDoc) { return @() }
    $primary = $RuleDoc.PSObject.Properties[$PrimaryName]
    if ($null -ne $primary) { return @($primary.Value) }
    if ($AliasName) {
        $alias = $RuleDoc.PSObject.Properties[$AliasName]
        if ($null -ne $alias) { return @($alias.Value) }
    }
    return @()
}

function Test-RuleMatch {
    param($Change, $Rule)
    if ($null -eq $Rule) { return $false }
    $match = $true
    $ruleSoftware = Get-ObjectPropertyValue -InputObject $Rule -Name 'software_id'
    $ruleClass = Get-ObjectPropertyValue -InputObject $Rule -Name 'classification'
    $keyRegex = Get-ObjectPropertyValue -InputObject $Rule -Name 'key_path_regex'
    $valueRegex = Get-ObjectPropertyValue -InputObject $Rule -Name 'value_name_regex'
    $reasonContains = Get-ObjectPropertyValue -InputObject $Rule -Name 'reason_contains'

    if ($ruleSoftware -and $SoftwareId -and ([string]$ruleSoftware -ne [string]$SoftwareId)) { $match = $false }
    if ($match -and $ruleClass -and ([string]$ruleClass -ne [string]$Change.classification)) { $match = $false }
    if ($match -and $keyRegex -and (-not ([string]$Change.key_path -match [string]$keyRegex))) { $match = $false }
    if ($match -and $valueRegex -and (-not ([string]$Change.value_name -match [string]$valueRegex))) { $match = $false }
    if ($match -and $reasonContains -and (-not ([string]$Change.reason -like "*$reasonContains*"))) { $match = $false }
    return $match
}

$errors = @()
$beforeSnapshot = Read-JsonFile -Path $BeforeSnapshotPath -Errors ([ref]$errors)
$afterSnapshot = Read-JsonFile -Path $AfterSnapshotPath -Errors ([ref]$errors)
$expectedDoc = Read-JsonFile -Path $ExpectedRulesPath -Errors ([ref]$errors)
$watchlistDoc = Read-JsonFile -Path $WatchlistPath -Errors ([ref]$errors)

$beforeEntries = @(Get-SnapshotEntries -Snapshot $beforeSnapshot)
$afterEntries = @(Get-SnapshotEntries -Snapshot $afterSnapshot)
$beforeMap = @{}
$afterMap = @{}

foreach ($item in $beforeEntries) {
    $keyPath = [string](Get-ObjectPropertyValue -InputObject $item -Name 'key_path' -Default (Get-ObjectPropertyValue -InputObject $item -Name 'path' -Default ''))
    $valueName = Get-ObjectPropertyValue -InputObject $item -Name 'value_name' -Default (Get-ObjectPropertyValue -InputObject $item -Name 'name' -Default $KeySentinelName)
    $normKey = Normalize-KeyPath -KeyPath $keyPath
    $normValue = if ($valueName -eq $KeySentinelName) { $KeySentinelName } else { Normalize-ValueName -ValueName ([string]$valueName) }
    $beforeMap["$normKey|$normValue"] = [pscustomobject]@{ key_path = $keyPath; value_name = $valueName; is_key_only = ($valueName -eq $KeySentinelName); state = New-ValueState -Item $item }
}

foreach ($item in $afterEntries) {
    $keyPath = [string](Get-ObjectPropertyValue -InputObject $item -Name 'key_path' -Default (Get-ObjectPropertyValue -InputObject $item -Name 'path' -Default ''))
    $valueName = Get-ObjectPropertyValue -InputObject $item -Name 'value_name' -Default (Get-ObjectPropertyValue -InputObject $item -Name 'name' -Default $KeySentinelName)
    $normKey = Normalize-KeyPath -KeyPath $keyPath
    $normValue = if ($valueName -eq $KeySentinelName) { $KeySentinelName } else { Normalize-ValueName -ValueName ([string]$valueName) }
    $afterMap["$normKey|$normValue"] = [pscustomobject]@{ key_path = $keyPath; value_name = $valueName; is_key_only = ($valueName -eq $KeySentinelName); state = New-ValueState -Item $item }
}

$allIds = @()
$allIds += @($beforeMap.Keys)
$allIds += @($afterMap.Keys)
$allIds = @($allIds | Sort-Object -Unique)

$changes = @()
foreach ($id in $allIds) {
    $before = if ($beforeMap.ContainsKey($id)) { $beforeMap[$id] } else { $null }
    $after = if ($afterMap.ContainsKey($id)) { $afterMap[$id] } else { $null }
    $baseClassification = $null
    $reason = $null
    if ($null -eq $before -and $null -ne $after) {
        $baseClassification = if ($after.is_key_only) { 'CreatedKey' } else { 'CreatedValue' }
        $reason = if ($after.is_key_only) { 'Registry key exists after snapshot only.' } else { 'Registry value exists after snapshot only.' }
    }
    elseif ($null -ne $before -and $null -eq $after) {
        $baseClassification = if ($before.is_key_only) { 'DeletedKey' } else { 'DeletedValue' }
        $reason = if ($before.is_key_only) { 'Registry key exists before snapshot only.' } else { 'Registry value exists before snapshot only.' }
    }
    elseif ($null -ne $before -and $null -ne $after -and -not $before.is_key_only -and -not $after.is_key_only) {
        $beforeJson = $before.state | ConvertTo-Json -Depth 20 -Compress
        $afterJson = $after.state | ConvertTo-Json -Depth 20 -Compress
        if ($beforeJson -ne $afterJson) {
            $baseClassification = 'ModifiedValue'
            $reason = 'Value data, type, data kind, or access status changed.'
        }
    }
    if (-not $baseClassification) { continue }
    $changes += [pscustomobject]@{
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
}

$expectedRules = @(Get-RuleSection -RuleDoc $expectedDoc -PrimaryName 'expected_change_rules' -AliasName 'expected_rules')
$noiseRules = @(Get-RuleSection -RuleDoc $watchlistDoc -PrimaryName 'noise_patterns' -AliasName 'noise_rules')
$suspiciousRules = @(Get-RuleSection -RuleDoc $watchlistDoc -PrimaryName 'suspicious_change_rules' -AliasName 'suspicious_rules')
$remediationRules = @(Get-RuleSection -RuleDoc $watchlistDoc -PrimaryName 'remediation_candidate_rules' -AliasName 'remediation_rules')

foreach ($change in $changes) {
    foreach ($ruleSet in @(
        [pscustomobject]@{ rules = $noiseRules; class = 'Noise'; confidence = 'high'; review = $false; defaultReason = 'Matched noise pattern.'; defaultId = 'noise-rule' },
        [pscustomobject]@{ rules = $expectedRules; class = 'ExpectedChange'; confidence = 'high'; review = $false; defaultReason = 'Matched expected change rule.'; defaultId = 'expected-rule' },
        [pscustomobject]@{ rules = $remediationRules; class = 'RemediationCandidate'; confidence = 'medium'; review = $true; defaultReason = 'Matched remediation candidate rule.'; defaultId = 'remediation-rule' },
        [pscustomobject]@{ rules = $suspiciousRules; class = 'SuspiciousChange'; confidence = 'medium'; review = $true; defaultReason = 'Matched suspicious change rule.'; defaultId = 'suspicious-rule' }
    )) {
        $matchedRule = @($ruleSet.rules | Where-Object { Test-RuleMatch -Change $change -Rule $_ } | Select-Object -First 1)
        if ($matchedRule.Count -gt 0) {
            $rule = $matchedRule[0]
            $change.classification = $ruleSet.class
            $change.reason = [string](Get-ObjectPropertyValue -InputObject $rule -Name 'reason' -Default $ruleSet.defaultReason)
            $change.matched_rule_id = [string](Get-ObjectPropertyValue -InputObject $rule -Name 'id' -Default $ruleSet.defaultId)
            $change.confidence = [string](Get-ObjectPropertyValue -InputObject $rule -Name 'confidence' -Default $ruleSet.confidence)
            $change.requires_review = [bool]$ruleSet.review
            break
        }
    }
}

$targetName = Get-ObjectPropertyValue -InputObject $afterSnapshot -Name 'target'
if (-not $targetName) { $targetName = Get-ObjectPropertyValue -InputObject $beforeSnapshot -Name 'target' -Default 'unknown' }

$result = [pscustomobject]@{
    schema_version = '1.0.0'
    run_id = [guid]::NewGuid().ToString()
    target = [string]$targetName
    software_id = if ($SoftwareId) { $SoftwareId } else { $null }
    compared_at = (Get-Date).ToString('o')
    before_snapshot = [pscustomobject]@{ path = $BeforeSnapshotPath; entries = @($beforeEntries).Count }
    after_snapshot = [pscustomobject]@{ path = $AfterSnapshotPath; entries = @($afterEntries).Count }
    summary = [pscustomobject]@{
        total_changes = @($changes).Count
        created_keys = @($changes | Where-Object { $_.base_classification -eq 'CreatedKey' }).Count
        deleted_keys = @($changes | Where-Object { $_.base_classification -eq 'DeletedKey' }).Count
        created_values = @($changes | Where-Object { $_.base_classification -eq 'CreatedValue' }).Count
        deleted_values = @($changes | Where-Object { $_.base_classification -eq 'DeletedValue' }).Count
        modified_values = @($changes | Where-Object { $_.base_classification -eq 'ModifiedValue' }).Count
        expected_changes = @($changes | Where-Object { $_.classification -eq 'ExpectedChange' }).Count
        noise_changes = @($changes | Where-Object { $_.classification -eq 'Noise' }).Count
        suspicious_changes = @($changes | Where-Object { $_.classification -eq 'SuspiciousChange' }).Count
        remediation_candidates = @($changes | Where-Object { $_.classification -eq 'RemediationCandidate' }).Count
        requires_review_count = @($changes | Where-Object { $_.requires_review -eq $true }).Count
    }
    changes = @($changes)
    errors = @($errors)
    output_paths = [pscustomobject]@{ json = $OutputJson; csv = $OutputCsv }
}

if ($OutputJson) { ($result | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $OutputJson -Encoding UTF8 }
if ($OutputCsv) {
    @($changes) | Select-Object classification, base_classification, key_path, value_name, reason, confidence, matched_rule_id, requires_review |
        Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
}
$result | ConvertTo-Json -Depth 20
