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
    $fileRows = @()
    foreach ($relativeFile in @($package.staged_files | ForEach-Object { [string]$_ })) {
        if ([string]::IsNullOrWhiteSpace($relativeFile) -or $relativeFile -match '(^|\\)\.\.(\\|$)') {
            throw "Unsafe staged file path in ${id}: $relativeFile"
        }
        $sourceFile = Join-Path $sourceFolder $relativeFile
        $exists = ($folderExists -and (Test-Path -LiteralPath $sourceFile -PathType Leaf))
        $sha256 = $null
        $length = $null
        if ($exists) {
            $item = Get-Item -LiteralPath $sourceFile -ErrorAction Stop
            $length = [int64]$item.Length
            $sha256 = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        else { $missingCount++ }
        $fileRows += [pscustomobject][ordered]@{
            relative_path = $relativeFile
            full_path = $sourceFile
            exists = $exists
            length = $length
            sha256 = $sha256
        }
    }
    $entrypoint = [string]$package.entrypoint_file
    $entrypointTracked = (@($package.staged_files | ForEach-Object { [string]$_ }) -contains $entrypoint)
    $actualInventory = @()
    if ($folderExists -and (@($fileRows | Where-Object { -not $_.exists }).Count -gt 0)) {
        $actualInventory = @(Get-ChildItem -LiteralPath $sourceFolder -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject][ordered]@{
                relative_path = $_.FullName.Substring($sourceFolder.Length).TrimStart('\')
                length = [int64]$_.Length
            }
        } | Sort-Object relative_path)
    }
    $rows += [pscustomobject][ordered]@{
        id = $id
        display_name = [string]$package.display_name
        source_folder = $sourceFolder
        source_folder_exists = $folderExists
        entrypoint_file = $entrypoint
        entrypoint_tracked = $entrypointTracked
        files = $fileRows
        actual_inventory_when_incomplete = $actualInventory
        complete = ($folderExists -and $entrypointTracked -and @($fileRows | Where-Object { -not $_.exists }).Count -eq 0)
    }
}

$ready = ($missingCount -eq 0 -and @($rows | Where-Object { -not $_.complete }).Count -eq 0)
$result = [pscustomobject][ordered]@{
    schema_version = 'sas-cybernet-clinical-core-source-preflight/v1'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    package_set_id = 'cybernet-clinical-core'
    package_count = $expectedIds.Count
    software_share_root = $shareRoot
    source_network_activity_performed = $true
    target_contact_performed = $false
    target_mutation_performed = $false
    ready_for_target_staging = $ready
    missing_file_count = $missingCount
    packages = $rows
    status = $(if ($ready) { 'CYBERNET_CLINICAL_CORE_SOURCES_READY' } else { 'CYBERNET_CLINICAL_CORE_SOURCES_INCOMPLETE' })
    result_path = $resultPath
}
$result | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $resultPath -Encoding UTF8

if ($ready) {
    Write-Host 'CYBERNET CLINICAL CORE SOURCES READY' -ForegroundColor Green
    Write-Host "Packages: $($expectedIds.Count) | Missing files: 0"
    Write-Host "Evidence: $resultPath"
    if ($PassThru) { $result }
    exit 0
}

Write-Host 'CYBERNET CLINICAL CORE SOURCES INCOMPLETE' -ForegroundColor Yellow
foreach ($package in @($rows | Where-Object { -not $_.complete })) {
    Write-Host "Package: $($package.id)" -ForegroundColor Yellow
    foreach ($file in @($package.files | Where-Object { -not $_.exists })) { Write-Host "  MISSING: $($file.full_path)" -ForegroundColor Red }
    if (@($package.actual_inventory_when_incomplete).Count -gt 0) {
        Write-Host '  Actual files present:' -ForegroundColor Cyan
        foreach ($item in @($package.actual_inventory_when_incomplete)) { Write-Host "    $($item.relative_path)" }
    }
}
Write-Host 'No target contact or mutation was performed by source preflight.' -ForegroundColor Green
Write-Host "Evidence: $resultPath"
if ($PassThru) { $result }
exit 42
