# Requires PowerShell 5.1+
<#
.SYNOPSIS
Captures a read-only registry snapshot for install-diff evidence collection.

.DESCRIPTION
Get-RegistrySnapshot.ps1 captures selected registry keys and values into a structured object
and optional JSON export. It is designed for the Registry Install Diff Pipeline evidence flow.

.PARAMETER Target
Capture target. Defaults to localhost.

.PARAMETER RegistryPath
Single registry root path to snapshot.

.PARAMETER RegistryPaths
Multiple registry root paths to snapshot.

.PARAMETER ExcludePattern
Single wildcard exclusion pattern applied to registry key paths.

.PARAMETER ExcludePatterns
Multiple wildcard exclusion patterns applied to registry key paths.

.PARAMETER OutputPath
Optional JSON output path for persisted snapshot evidence.

.EXAMPLE
powershell.exe -File scripts/powershell/Get-RegistrySnapshot.ps1 -Target localhost

.NOTES
Safety notes: read-only evidence capture only. No registry writes, installer execution, remoting changes, or service changes are performed.
#>
[CmdletBinding()]
param(
    [string]$Target = 'localhost',
    [string]$RegistryPath,
    [string[]]$RegistryPaths,
    [string]$ExcludePattern,
    [string[]]$ExcludePatterns,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$defaultRegistryPaths = @(
    'HKLM:\Software',
    'HKLM:\Software\WOW6432Node',
    'HKLM:\System\CurrentControlSet\Services',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
)

$effectiveRegistryPaths = @()
if ($RegistryPath) { $effectiveRegistryPaths += $RegistryPath }
if ($RegistryPaths) { $effectiveRegistryPaths += $RegistryPaths }
if (@($effectiveRegistryPaths).Count -eq 0) { $effectiveRegistryPaths = $defaultRegistryPaths }
$effectiveRegistryPaths = @($effectiveRegistryPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

$effectiveExcludePatterns = @()
if ($ExcludePattern) { $effectiveExcludePatterns += $ExcludePattern }
if ($ExcludePatterns) { $effectiveExcludePatterns += $ExcludePatterns }
$effectiveExcludePatterns = @($effectiveExcludePatterns | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

function Get-ValueDataKind {
    param([object]$Value)
    if ($null -eq $Value) { return 'unknown' }
    if ($Value -is [string]) {
        if ($Value -match '%[^%]+%') { return 'expandable_string' }
        return 'string'
    }
    if ($Value -is [int]) { return 'dword' }
    if ($Value -is [long]) { return 'qword' }
    if ($Value -is [byte[]]) { return 'binary' }
    if ($Value -is [string[]]) { return 'multi_string' }
    return 'unknown'
}

function Convert-ValueData {
    param([object]$Value)
    if ($Value -is [byte[]]) { return [Convert]::ToBase64String($Value) }
    return $Value
}

function Test-IsExcluded {
    param([string]$Path, [string[]]$Patterns)
    foreach ($pattern in @($Patterns)) {
        if ($Path -like $pattern) { return $true }
    }
    return $false
}

function New-SnapshotEntry {
    param(
        [string]$KeyPath,
        [object]$ValueName,
        [object]$ValueType,
        [object]$ValueData,
        [string]$ValueDataKind = 'unknown',
        [string]$AccessStatus,
        [string]$ErrorMessage
    )
    [pscustomobject]@{
        key_path        = $KeyPath
        value_name      = $ValueName
        value_type      = $ValueType
        value_data      = $ValueData
        value_data_kind = $ValueDataKind
        captured_at     = (Get-Date).ToString('o')
        access_status   = $AccessStatus
        error_message   = $ErrorMessage
    }
}

$capturedAt = (Get-Date).ToString('o')
$runId = [guid]::NewGuid().ToString()
$hostName = $env:COMPUTERNAME
$scope = 'localhost'
$targetNotes = 'Read-only local capture completed.'
$localAliases = @('localhost', '.', $env:COMPUTERNAME)
if ($localAliases -notcontains $Target) {
    $scope = 'remote'
    $targetNotes = 'RemoteRegistrySnapshotNotImplemented'
}

$summary = [pscustomobject]@{
    roots_requested = @($effectiveRegistryPaths).Count
    keys_scanned    = 0
    entries_total   = 0
    captured        = 0
    access_denied   = 0
    not_found       = 0
    errors          = 0
    excluded        = 0
}

$result = [pscustomobject]@{
    schema_version = '1.0.0'
    run_id = $runId
    target = [pscustomobject]@{ hostname = if ($Target) { $Target } else { $hostName }; scope = $scope; notes = $targetNotes }
    captured_at = $capturedAt
    source = [pscustomobject]@{ script = 'scripts/powershell/Get-RegistrySnapshot.ps1'; mode = 'read_only' }
    registry_paths = $effectiveRegistryPaths
    entries = @()
    errors = @()
    summary = $summary
    output_path = $OutputPath
}

if ($scope -ne 'localhost') {
    $result.errors += [pscustomobject]@{ key_path = $null; access_status = 'Error'; error_message = 'RemoteRegistrySnapshotNotImplemented'; captured_at = (Get-Date).ToString('o') }
    $result.summary.errors = 1
}
else {
    foreach ($rootPath in @($effectiveRegistryPaths)) {
        if (Test-IsExcluded -Path $rootPath -Patterns $effectiveExcludePatterns) {
            $result.summary.excluded++
            continue
        }
        if (-not (Test-Path -LiteralPath $rootPath)) {
            $result.entries += (New-SnapshotEntry -KeyPath $rootPath -ValueName $null -ValueType $null -ValueData $null -AccessStatus 'NotFound' -ErrorMessage 'Registry path not found.')
            $result.summary.entries_total++
            $result.summary.not_found++
            continue
        }

        $pending = New-Object System.Collections.Generic.Queue[string]
        $pending.Enqueue($rootPath)
        while ($pending.Count -gt 0) {
            $currentPath = $pending.Dequeue()
            if (Test-IsExcluded -Path $currentPath -Patterns $effectiveExcludePatterns) {
                $result.summary.excluded++
                continue
            }
            $result.summary.keys_scanned++
            try {
                $item = Get-Item -LiteralPath $currentPath -ErrorAction Stop
                $valueNames = @($item.GetValueNames())
                if (@($valueNames).Count -eq 0) {
                    $result.entries += (New-SnapshotEntry -KeyPath $currentPath -ValueName $null -ValueType $null -ValueData $null -AccessStatus 'Captured' -ErrorMessage $null)
                    $result.summary.entries_total++
                    $result.summary.captured++
                } else {
                    foreach ($valueName in @($valueNames)) {
                        $rawValue = $item.GetValue($valueName, $null)
                        $result.entries += (New-SnapshotEntry -KeyPath $currentPath -ValueName $(if ([string]::IsNullOrEmpty($valueName)) { '(Default)' } else { $valueName }) -ValueType $item.GetValueKind($valueName).ToString() -ValueData (Convert-ValueData -Value $rawValue) -ValueDataKind (Get-ValueDataKind -Value $rawValue) -AccessStatus 'Captured' -ErrorMessage $null)
                        $result.summary.entries_total++
                        $result.summary.captured++
                    }
                }
                try {
                    $children = @(Get-ChildItem -LiteralPath $currentPath -ErrorAction Stop)
                    foreach ($child in @($children)) {
                        $childPath = $child.PSPath.Replace('Microsoft.PowerShell.Core\Registry::', '')
                        if (Test-IsExcluded -Path $childPath -Patterns $effectiveExcludePatterns) { $result.summary.excluded++ }
                        else { $pending.Enqueue($childPath) }
                    }
                } catch {
                    $result.errors += [pscustomobject]@{ key_path = $currentPath; access_status = 'Error'; error_message = $_.Exception.Message; captured_at = (Get-Date).ToString('o') }
                    $result.summary.errors++
                }
            } catch {
                $message = $_.Exception.Message
                $status = if ($message -match 'denied') { 'AccessDenied' } else { 'Error' }
                $result.entries += (New-SnapshotEntry -KeyPath $currentPath -ValueName $null -ValueType $null -ValueData $null -AccessStatus $status -ErrorMessage $message)
                $result.summary.entries_total++
                if ($status -eq 'AccessDenied') { $result.summary.access_denied++ } else { $result.summary.errors++ }
            }
        }
    }
}

if ($OutputPath) {
    $outDir = Split-Path -Path $OutputPath -Parent
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    ($result | ConvertTo-Json -Depth 8) | Set-Content -Path $OutputPath -Encoding UTF8
}
$result
