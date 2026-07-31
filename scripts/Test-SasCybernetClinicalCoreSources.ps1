#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$catalogPath = Join-Path $repoRoot 'configs\software-packages\windows-native-package-sets.json'
$harnessApiPath = Join-Path $repoRoot 'harness\api\sas-harness-api.json'
foreach ($required in @($catalogPath,$harnessApiPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing source-preflight dependency: $required" }
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$catalog.schema_version -ne 'sas-windows-native-package-sets/v1') { throw 'Unsupported package-set catalog schema.' }
$set = @($catalog.package_sets | Where-Object { [string]$_.id -eq 'cybernet-clinical-core' })
if ($set.Count -ne 1) { throw 'cybernet-clinical-core package set is missing or ambiguous.' }
$expectedIds = @(
    'allscripts-eehr-shortcut-uai-2-2',
    'epic-downtime-guide-shortcut-1-0',
    'nuance-dragon-medical-one-2025',
    'hyland-fos-epic-integration-23-1-33-1000',
    'bca'
)
$setIds = @($set[0].package_ids | ForEach-Object { [string]$_ })
if (($setIds -join '|') -ne ($expectedIds -join '|') -or $setIds -contains 'autologon') {
    throw 'Tracked clinical-core membership/order is not the approved five-package set.'
}

$shareRoot = ([string]$catalog.software_share_root).Trim().TrimEnd('\')
$harnessApi = Get-Content -LiteralPath $harnessApiPath -Raw -Encoding UTF8 | ConvertFrom-Json
$approvedRoots = @($harnessApi.posture.approved_software_sources | ForEach-Object { ([string]$_).Trim().TrimEnd('\') })
if (@($approvedRoots | Where-Object { $_.Equals($shareRoot,[StringComparison]::OrdinalIgnoreCase) }).Count -ne 1) {
    throw "Software share root is not the single approved package source: $shareRoot"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'survey\output\runs\cybernet-clinical-core-source-preflight'
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$runId = 'cybernet-core-source-preflight-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$resultPath = Join-Path $runRoot 'cybernet_clinical_core_source_preflight.json'

$packageById = @{}
foreach ($package in @($catalog.packages)) { $packageById[[string]$package.id] = $package }
$rows = @()
foreach ($id in $expectedIds) {
    if (-not $packageById.ContainsKey($id)) { throw "Missing package definition: $id" }
    $package = $packageById[$id]
    if (-not [bool]$package.install_enabled) { throw "Package is disabled: $id" }
    $sourceFolder = Join-Path $shareRoot ([string]$package.source_folder_relative_path)
    $folderExists = Test-Path -LiteralPath $sourceFolder -PathType Container
    $entrypoint = [string]$package.entrypoint_file
    $entrypointPath = Join-Path $sourceFolder $entrypoint
    $entrypointExists = ($folderExists -and (Test-Path -LiteralPath $entrypointPath -PathType Leaf))
    $actualFiles = @()
    $missingFiles = @()
    $trackedFiles = @()
    $unexpectedFiles = @()
    $inventoryDrift = $false
    $selection = $null

    if ([string]$package.package_kind -eq 'bundle') {
        $selection = 'all_files_recursive_from_approved_bundle_folder'
        if ($folderExists) {
            $actualFiles = @(Get-ChildItem -LiteralPath $sourceFolder -Recurse -File -ErrorAction Stop)
        }
        if ($package.PSObject.Properties['staged_files']) {
            $trackedFiles = @($package.staged_files | ForEach-Object { ([string]$_).TrimStart('\') } | Where-Object { $_ })
            $actualRelative = @($actualFiles | ForEach-Object { $_.FullName.Substring($sourceFolder.Length).TrimStart('\') })
            $missingFiles = @($trackedFiles | Where-Object { $_ -notin $actualRelative })
            $unexpectedFiles = @($actualRelative | Where-Object { $_ -notin $trackedFiles })
            $inventoryDrift = ($missingFiles.Count -gt 0 -or $unexpectedFiles.Count -gt 0)
        }
    }
    else {
        $selection = 'tracked_staged_files_only'
        $trackedFiles = @($package.staged_files | ForEach-Object { [string]$_ })
        foreach ($relativeFile in $trackedFiles) {
            if ([string]::IsNullOrWhiteSpace($relativeFile) -or $relativeFile -match '(^|\\)\.\.(\\|$)') { throw "Unsafe staged file path in ${id}: $relativeFile" }
            $sourceFile = Join-Path $sourceFolder $relativeFile
            if ($folderExists -and (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { $actualFiles += Get-Item -LiteralPath $sourceFile -ErrorAction Stop }
            else { $missingFiles += $relativeFile }
        }
        $inventoryDrift = ($missingFiles.Count -gt 0)
    }

    $fileRows = @($actualFiles | ForEach-Object {
        [pscustomobject][ordered]@{
            relative_path = $_.FullName.Substring($sourceFolder.Length).TrimStart('\')
            full_path = $_.FullName
            exists = $true
            length = [int64]$_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } | Sort-Object relative_path)

    $complete = ($folderExists -and $entrypointExists -and $fileRows.Count -gt 0)
    if ([string]$package.package_kind -ne 'bundle') {
        $complete = ($complete -and $missingFiles.Count -eq 0 -and $fileRows.Count -eq $trackedFiles.Count)
    }

    $rows += [pscustomobject][ordered]@{
        id = $id
        display_name = [string]$package.display_name
        package_kind = [string]$package.package_kind
        source_folder = $sourceFolder
        source_folder_exists = $folderExists
        expected_entrypoint = $entrypoint
        expected_entrypoint_path = $entrypointPath
        entrypoint_exists = $entrypointExists
        source_selection = $selection
        tracked_files = $trackedFiles
        actual_files = $fileRows
        missing_files = $missingFiles
        unexpected_files = $unexpectedFiles
        inventory_drift = $inventoryDrift
        drift_interpretation = $(if ([string]$package.package_kind -eq 'bundle') { 'reported_not_silently_ignored; approved bundle directory is runtime staging authority' } else { 'blocking_for_single_package' })
        ready = $complete
    }
}

$notReady = @($rows | Where-Object { -not $_.ready })
$ready = ($notReady.Count -eq 0)
$result = [pscustomobject][ordered]@{
    schema_version = 'sas-cybernet-clinical-core-source-preflight/v2'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    package_set_id = 'cybernet-clinical-core'
    package_count = $expectedIds.Count
    software_share_root = $shareRoot
    bundle_source_policy = 'copy_and_hash_all_files_recursive_from_approved_bundle_folder'
    single_source_policy = 'copy_and_hash_tracked_staged_files_only'
    source_network_activity_performed = $true
    target_contact_performed = $false
    target_mutation_performed = $false
    ready_for_target_staging = $ready
    missing_or_invalid_source_count = $notReady.Count
    inventory_drift_package_count = @($rows | Where-Object { $_.inventory_drift }).Count
    packages = $rows
    status = $(if ($ready) { 'CYBERNET_CLINICAL_CORE_SOURCES_READY' } else { 'CYBERNET_CLINICAL_CORE_SOURCES_INCOMPLETE' })
    result_path = $resultPath
}
$result | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $resultPath -Encoding UTF8

if ($ready) {
    Write-Host 'CYBERNET CLINICAL CORE SOURCES READY' -ForegroundColor Green
    Write-Host "Packages: $($expectedIds.Count) | Bundle folders use complete recursive source authority."
    if ($result.inventory_drift_package_count -gt 0) { Write-Host "Inventory drift reported for $($result.inventory_drift_package_count) bundle package(s); see evidence." -ForegroundColor Yellow }
    Write-Host "Evidence: $resultPath"
    if ($PassThru) { $result }
    exit 0
}

Write-Host 'CYBERNET CLINICAL CORE SOURCES INCOMPLETE' -ForegroundColor Yellow
foreach ($package in $notReady) {
    Write-Host "Package: $($package.id)" -ForegroundColor Yellow
    Write-Host "  Source folder exists: $($package.source_folder_exists)"
    Write-Host "  Entrypoint exists: $($package.entrypoint_exists)"
    Write-Host "  Files observed: $(@($package.actual_files).Count)"
    if (@($package.missing_files).Count -gt 0) { Write-Host "  Missing: $(@($package.missing_files) -join ', ')" }
}
Write-Host 'No target contact or mutation was performed by source preflight.' -ForegroundColor Green
Write-Host "Evidence: $resultPath"
if ($PassThru) { $result }
exit 42