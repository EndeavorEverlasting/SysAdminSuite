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
$missingCount = 0
foreach ($id in $expectedIds) {
    if (-not $packageById.ContainsKey($id)) { throw "Missing package definition: $id" }
    $package = $packageById[$id]
    if (-not [bool]$package.install_enabled) { throw "Package is disabled: $id" }
    $sourceFolder = Join-Path $shareRoot ([string]$package.source_folder_relative_path)
    $folderExists = Test-Path -LiteralPath $sourceFolder -PathType Container
    $entrypoint = [string]$package.entrypoint_file
    $sourceFiles = @()
    if ($folderExists) {
        if ([string]$package.package_kind -eq 'bundle') {
            $sourceFiles = @(Get-ChildItem -LiteralPath $sourceFolder -Recurse -File -ErrorAction Stop)
        }
        else {
            foreach ($relativeFile in @($package.staged_files | ForEach-Object { [string]$_ })) {
                if ([string]::IsNullOrWhiteSpace($relativeFile) -or $relativeFile -match '(^|\\)\.\.(\\|$)') {
                    throw "Unsafe staged file path in ${id}: $relativeFile"
                }
                $sourceFile = Join-Path $sourceFolder $relativeFile
                if (Test-Path -LiteralPath $sourceFile -PathType Leaf) { $sourceFiles += Get-Item -LiteralPath $sourceFile -ErrorAction Stop }
                else { $missingCount++ }
            }
        }
    }
    else { $missingCount++ }

    $fileRows = @($sourceFiles | ForEach-Object {
        [pscustomobject][ordered]@{
            relative_path = $_.FullName.Substring($sourceFolder.Length).TrimStart('\')
            full_path = $_.FullName
            exists = $true
            length = [int64]$_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } | Sort-Object relative_path)

    $entrypointPath = Join-Path $sourceFolder $entrypoint
    $entrypointExists = ($folderExists -and (Test-Path -LiteralPath $entrypointPath -PathType Leaf))
    if (-not $entrypointExists) { $missingCount++ }
    $complete = ($folderExists -and $entrypointExists -and $fileRows.Count -gt 0 -and $missingCount -ge 0)
    if ([string]$package.package_kind -ne 'bundle') {
        $expectedFileCount = @($package.staged_files).Count
        $complete = ($complete -and $fileRows.Count -eq $expectedFileCount)
    }
    $rows += [pscustomobject][ordered]@{
        id = $id
        display_name = [string]$package.display_name
        package_kind = [string]$package.package_kind
        source_folder = $sourceFolder
        source_folder_exists = $folderExists
        entrypoint_file = $entrypoint
        entrypoint_exists = $entrypointExists
        source_selection = $(if ([string]$package.package_kind -eq 'bundle') { 'all_files_recursive_from_approved_bundle_folder' } else { 'tracked_staged_files_only' })
        files = $fileRows
        complete = $complete
    }
}

$ready = (@($rows | Where-Object { -not $_.complete }).Count -eq 0)
$result = [pscustomobject][ordered]@{
    schema_version = 'sas-cybernet-clinical-core-source-preflight/v1'
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
    missing_or_invalid_source_count = @($rows | Where-Object { -not $_.complete }).Count
    packages = $rows
    status = $(if ($ready) { 'CYBERNET_CLINICAL_CORE_SOURCES_READY' } else { 'CYBERNET_CLINICAL_CORE_SOURCES_INCOMPLETE' })
    result_path = $resultPath
}
$result | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $resultPath -Encoding UTF8

if ($ready) {
    Write-Host 'CYBERNET CLINICAL CORE SOURCES READY' -ForegroundColor Green
    Write-Host "Packages: $($expectedIds.Count) | Bundle folders are complete recursive source authorities."
    Write-Host "Evidence: $resultPath"
    if ($PassThru) { $result }
    exit 0
}

Write-Host 'CYBERNET CLINICAL CORE SOURCES INCOMPLETE' -ForegroundColor Yellow
foreach ($package in @($rows | Where-Object { -not $_.complete })) {
    Write-Host "Package: $($package.id)" -ForegroundColor Yellow
    Write-Host "  Source folder exists: $($package.source_folder_exists)"
    Write-Host "  Entrypoint exists: $($package.entrypoint_exists)"
    Write-Host "  Files observed: $(@($package.files).Count)"
}
Write-Host 'No target contact or mutation was performed by source preflight.' -ForegroundColor Green
Write-Host "Evidence: $resultPath"
if ($PassThru) { $result }
exit 42
