# Requires PowerShell 5.1+
<#
.SYNOPSIS
Captures a read-only registry snapshot for install-diff evidence collection.

.DESCRIPTION
Get-RegistrySnapshot.ps1 captures selected registry keys and values into a structured object
and optional JSON export. It is designed for the Registry Install Diff Pipeline evidence flow
(Recon -> Decide -> Act -> Log -> Export).

By default, the script inspects:
- HKLM:\Software
- HKLM:\Software\WOW6432Node
- HKLM:\System\CurrentControlSet\Services
- HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall

If -Target is not localhost (or local machine aliases), remote capture is not implemented in this
sprint. The script returns a structured result with an error reason of
RemoteRegistrySnapshotNotImplemented and does not modify remoting, services, or credentials.

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
Safety notes:
- Read-only evidence capture only.
- No registry writes, installer execution, remoting changes, or service changes are performed.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Target = 'localhost',

    [Parameter()]
    [string]$RegistryPath,

    [Parameter()]
    [string[]]$RegistryPaths,

    [Parameter()]
    [string]$ExcludePattern,

    [Parameter()]
    [string[]]$ExcludePatterns,

    [Parameter()]
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
if (-not $effectiveRegistryPaths -or @($effectiveRegistryPaths).Count -eq 0) {
    $effectiveRegistryPaths = $defaultRegistryPaths
}
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
    param(
        [string]$Path,
        [string[]]$Patterns
    )
    foreach ($pattern in @($Patterns)) {
        if ($Path -like $pattern) { return $true }
    }
    return $false
}

$capturedAt = (Get-Date).ToString('o')
$runId = [guid]::NewGuid().ToString()
$hostName = $env:COMPUTERNAME
$scope = 'localhost'
$targetNotes = 'Read-only local capture completed.'

$localAliases = @('localhost', '.', $env:COMPUTERNAME)
if ($localAliases -notcontains $Target) {
    $scope = 'remote'
    $targetNotes = 'Remote registry snapshot is not implemented in this sprint.'
}

$result = [ordered]@{
    schema_version = '1.0.0'
    run_id         = $runId
    target         = [ordered]@{
        hostname = if ($Target) { $Target } else { $hostName }
        scope    = $scope
        notes    = $targetNotes
    }
    captured_at    = $capturedAt
    source         = [ordered]@{
        script = 'scripts/powershell/Get-RegistrySnapshot.ps1'
        mode   = 'read_only'
    }
    registry_paths = $effectiveRegistryPaths
    entries        = @()
    errors         = @()
    summary        = [ordered]@{
        roots_requested = @($effectiveRegistryPaths).Count
        keys_scanned    = 0
        entries_total   = 0
        captured        = 0
        access_denied   = 0
        not_found       = 0
        errors          = 0
        excluded        = 0
    }
    output_path    = $OutputPath
}

if ($scope -ne 'localhost') {
    $result.target.scope = 'remote'
    $result.target.notes = 'RemoteRegistrySnapshotNotImplemented'
    $result.errors += [ordered]@{
        key_path      = $null
        access_status = 'Error'
        error_message = 'RemoteRegistrySnapshotNotImplemented'
        captured_at   = (Get-Date).ToString('o')
    }
    $result.summary.errors = 1
}
else {
    foreach ($rootPath in @($effectiveRegistryPaths)) {
        if (Test-IsExcluded -Path $rootPath -Patterns $effectiveExcludePatterns) {
            $result.summary.excluded++
            continue
        }

        if (-not (Test-Path -LiteralPath $rootPath)) {
            $missingEntry = [ordered]@{
                key_path        = $rootPath
                value_name      = $null
                value_type      = $null
                value_data      = $null
                value_data_kind = 'unknown'
                captured_at     = (Get-Date).ToString('o')
                access_status   = 'NotFound'
                error_message   = 'Registry path not found.'
            }
            $result.entries += $missingEntry
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
                    $result.entries += [ordered]@{
                        key_path        = $currentPath
                        value_name      = $null
                        value_type      = $null
                        value_data      = $null
                        value_data_kind = 'unknown'
                        captured_at     = (Get-Date).ToString('o')
                        access_status   = 'Captured'
                        error_message   = $null
                    }
                    $result.summary.entries_total++
                    $result.summary.captured++
                }
                else {
                    foreach ($valueName in @($valueNames)) {
                        $rawValue = $item.GetValue($valueName, $null)
                        $kind = Get-ValueDataKind -Value $rawValue
                        $valueData = Convert-ValueData -Value $rawValue
                        $valueKind = $item.GetValueKind($valueName).ToString()
                        $result.entries += [ordered]@{
                            key_path        = $currentPath
                            value_name      = if ([string]::IsNullOrEmpty($valueName)) { '(Default)' } else { $valueName }
                            value_type      = $valueKind
                            value_data      = $valueData
                            value_data_kind = $kind
                            captured_at     = (Get-Date).ToString('o')
                            access_status   = 'Captured'
                            error_message   = $null
                        }
                        $result.summary.entries_total++
                        $result.summary.captured++
                    }
                }

                try {
                    $children = @(Get-ChildItem -LiteralPath $currentPath -ErrorAction Stop)
                    foreach ($child in @($children)) {
                        $childPath = $child.PSPath.Replace('Microsoft.PowerShell.Core\Registry::', '')
                        if (-not (Test-IsExcluded -Path $childPath -Patterns $effectiveExcludePatterns)) {
                            $pending.Enqueue($childPath)
                        }
                        else {
                            $result.summary.excluded++
                        }
                    }
                }
                catch {
                    $result.errors += [ordered]@{
                        key_path      = $currentPath
                        access_status = 'Error'
                        error_message = $_.Exception.Message
                        captured_at   = (Get-Date).ToString('o')
                    }
                    $result.summary.errors++
                }
            }
            catch {
                $message = $_.Exception.Message
                $status = if ($message -match 'denied') { 'AccessDenied' } else { 'Error' }
                $result.entries += [ordered]@{
                    key_path        = $currentPath
                    value_name      = $null
                    value_type      = $null
                    value_data      = $null
                    value_data_kind = 'unknown'
                    captured_at     = (Get-Date).ToString('o')
                    access_status   = $status
                    error_message   = $message
                }
                $result.summary.entries_total++
                if ($status -eq 'AccessDenied') { $result.summary.access_denied++ }
                else { $result.summary.errors++ }
            }
        }
    }
}

if ($OutputPath) {
    $outDir = Split-Path -Path $OutputPath -Parent
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    ($result | ConvertTo-Json -Depth 8) | Set-Content -Path $OutputPath -Encoding UTF8
}

$result
