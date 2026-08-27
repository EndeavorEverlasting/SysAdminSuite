#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$MachineProfile,
    [string]$DesktopDevRoot,
    [string]$CandidatePath,
    [switch]$RequireCheckout,
    [switch]$AsJson
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$registryPath = Join-Path $repoRoot 'harness\api\canonical-path-registry.json'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    throw "Canonical path registry is missing: $registryPath"
}
$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
if ([string]$registry.repository -ne 'EndeavorEverlasting/SysAdminSuite') {
    throw "Unexpected canonical path registry repository identity: $($registry.repository)"
}

$isWindowsHost = ($env:OS -eq 'Windows_NT')
if (-not $isWindowsHost) {
    throw 'Resolve-SasCanonicalDevelopmentPath.ps1 currently owns Windows path resolution only; use the registered Linux/macOS profile workflow on those platforms.'
}

$selectedProfileId = if ([string]::IsNullOrWhiteSpace($MachineProfile)) { [string]$registry.default_profile } else { $MachineProfile.Trim() }
$profiles = @($registry.profiles | Where-Object { [string]$_.id -eq $selectedProfileId })
if ($profiles.Count -ne 1) {
    throw "Canonical path profile must resolve exactly once: $selectedProfileId"
}
$profile = $profiles[0]
if ([string]$profile.platform -ne 'windows') {
    throw "Profile '$selectedProfileId' is not compatible with this Windows resolver."
}

$user = if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) { [string]$env:USERNAME } else { [Environment]::UserName }
if ([string]::IsNullOrWhiteSpace($user)) { throw 'Unable to resolve current Windows user identity.' }

$oneDriveRoots = New-Object 'System.Collections.Generic.List[string]'
foreach ($raw in @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer)) {
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { continue }
    try { $full = [IO.Path]::GetFullPath([string]$raw) } catch { continue }
    if (-not $oneDriveRoots.Contains($full)) { [void]$oneDriveRoots.Add($full) }
}
$availableOneDriveRoots = @($oneDriveRoots | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
$oneDriveState = if ($oneDriveRoots.Count -eq 0) {
    'ABSENT'
} elseif ($availableOneDriveRoots.Count -eq 0) {
    'ROOT_UNAVAILABLE'
} elseif ($availableOneDriveRoots.Count -gt 1) {
    'MULTIPLE_ROOTS'
} else {
    'ROOT_AVAILABLE'
}

$desktopSource = 'os_known_folder'
if (-not [string]::IsNullOrWhiteSpace($DesktopDevRoot)) {
    try { $desktopDev = [IO.Path]::GetFullPath($DesktopDevRoot.Trim()) } catch { throw "Invalid explicit Desktop Dev root: $DesktopDevRoot" }
    $desktopSource = 'explicit_desktop_dev_root'
    $desktop = Split-Path -Parent $desktopDev
} else {
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
    if ([string]::IsNullOrWhiteSpace($desktop)) {
        throw 'Windows Desktop Known Folder could not be resolved. Canonical development location is UNKNOWN; no fallback clone is authorized.'
    }
    try { $desktop = [IO.Path]::GetFullPath($desktop) } catch { throw "Windows Desktop Known Folder is invalid: $desktop" }
    $desktopDev = Join-Path $desktop 'Dev'
}

foreach ($root in $availableOneDriveRoots) {
    $prefix = $root.TrimEnd('\') + '\'
    if ($desktop.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or $desktop.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        $oneDriveState = 'TARGET_FOLDER_REDIRECTED'
        break
    }
}

$template = [string]$profile.canonical_development_checkout.template
if ($template -ne '{desktop_dev_root}\SysAdminSuite') {
    throw "Unsupported Windows canonical development template: $template"
}
$canonicalDev = [IO.Path]::GetFullPath((Join-Path $desktopDev 'SysAdminSuite'))

if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required to resolve the canonical worktree root.' }
$worktreeRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'SysAdminSuite\worktrees'))

$productionApplicable = [bool]$profile.production_use_path.applicable
$productionUse = $null
if ($productionApplicable) {
    $productionUse = [Environment]::ExpandEnvironmentVariables([string]$profile.production_use_path.template)
    $productionUse = [IO.Path]::GetFullPath($productionUse)
}
$pathRelation = if ($productionApplicable) {
    'SEPARATE_EXPLICIT_SYNC_INSTALL_PROMOTION_REQUIRED'
} else {
    'DEVELOPMENT_PROFILE_ONLY_PRODUCTION_NOT_APPLICABLE'
}
$entrypointAuthority = [string]$profile.real_operator_entrypoint.authority
$canonicalEntrypoint = $null
$entrypointProperty = $profile.real_operator_entrypoint.PSObject.Properties['production_runtime_entrypoint']
if ($null -ne $entrypointProperty -and -not [string]::IsNullOrWhiteSpace([string]$entrypointProperty.Value)) {
    $canonicalEntrypoint = [Environment]::ExpandEnvironmentVariables([string]$entrypointProperty.Value)
}

$currentCandidate = if ([string]::IsNullOrWhiteSpace($CandidatePath)) { (Get-Location).Path } else { $CandidatePath.Trim() }
try { $currentCandidate = [IO.Path]::GetFullPath($currentCandidate) } catch { $currentCandidate = $null }
$candidateClassification = 'UNKNOWN'
if ($null -ne $currentCandidate) {
    if ($currentCandidate.Equals($canonicalDev, [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'CANONICAL_DEVELOPMENT'
    } elseif ($productionApplicable -and $currentCandidate.Equals($productionUse, [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'PRODUCTION_USE'
    } elseif ($currentCandidate.StartsWith($worktreeRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'ISOLATED_WORKTREE'
    } elseif ($env:LOCALAPPDATA -and $currentCandidate.StartsWith(([IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'SysAdminSuite\closeout-entry-'))), [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'EPHEMERAL_ACQUISITION'
    }
}

$checkoutStatus = 'MISSING'
$checkoutHead = $null
$checkoutRemote = $null
$canonicalReparseState = 'NOT_INSPECTED_MISSING'
if (Test-Path -LiteralPath $canonicalDev -PathType Container) {
    $canonicalItem = Get-Item -LiteralPath $canonicalDev -Force
    if (($canonicalItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $canonicalReparseState = 'REPARSE_POINT_PRESENT'
        $checkoutStatus = 'CONFLICT_REPARSE_POINT_UNINSPECTED'
    } else {
        $canonicalReparseState = 'NORMAL_DIRECTORY'
        $git = Get-Command git -ErrorAction SilentlyContinue
        if ($null -eq $git) {
            $checkoutStatus = 'UNKNOWN_GIT_UNAVAILABLE'
        } else {
            $top = (& git -C $canonicalDev rev-parse --show-toplevel 2>$null)
            $topExit = $LASTEXITCODE
            if ($topExit -ne 0 -or [string]::IsNullOrWhiteSpace([string]$top)) {
                $checkoutStatus = 'CONFLICT_NOT_GIT_CHECKOUT'
            } else {
                try { $topFull = [IO.Path]::GetFullPath(([string]$top).Trim()) } catch { $topFull = '' }
                if (-not $topFull.Equals($canonicalDev, [StringComparison]::OrdinalIgnoreCase)) {
                    $checkoutStatus = 'CONFLICT_NESTED_OR_WRONG_ROOT'
                } else {
                    $checkoutRemote = (& git -C $canonicalDev config --get remote.origin.url 2>$null)
                    $remoteExit = $LASTEXITCODE
                    $checkoutHead = (& git -C $canonicalDev rev-parse HEAD 2>$null)
                    $headExit = $LASTEXITCODE
                    $remoteText = ([string]$checkoutRemote).Trim()
                    $remoteMatches = $remoteExit -eq 0 -and $remoteText -match '(?i)(?:github\.com[:/])EndeavorEverlasting/SysAdminSuite(?:\.git)?$'
                    if (-not $remoteMatches) {
                        $checkoutStatus = 'CONFLICT_WRONG_REPOSITORY'
                    } elseif ($headExit -ne 0 -or ([string]$checkoutHead).Trim() -notmatch '^[0-9a-fA-F]{40}$') {
                        $checkoutStatus = 'UNKNOWN_GIT_IDENTITY'
                    } else {
                        $checkoutStatus = 'CANONICAL_PROVED'
                        $checkoutHead = ([string]$checkoutHead).Trim().ToLowerInvariant()
                        $checkoutRemote = $remoteText
                    }
                }
            }
        }
    }
}

$pathDisposition = if ($checkoutStatus -eq 'CANONICAL_PROVED' -and $candidateClassification -eq 'CANONICAL_DEVELOPMENT') {
    'CANONICAL + PROVED'
} elseif ($checkoutStatus -eq 'MISSING') {
    'MISSING'
} elseif ($checkoutStatus.StartsWith('CONFLICT', [StringComparison]::OrdinalIgnoreCase)) {
    'CONFLICT'
} elseif ($candidateClassification -eq 'ISOLATED_WORKTREE' -or $candidateClassification -eq 'EPHEMERAL_ACQUISITION') {
    'NONCANONICAL + PRESERVE'
} else {
    'UNKNOWN'
}

$receipt = [ordered]@{
    schema_version = 'sas-canonical-path-input-receipt/v1'
    repository = 'EndeavorEverlasting/SysAdminSuite'
    selected_profile = $selectedProfileId
    os = 'windows'
    path_semantics = 'WINDOWS_CASE_INSENSITIVE_NORMALIZED_FULL_PATH'
    user = $user
    desktop_known_folder = $desktop
    desktop_dev_root = $desktopDev
    desktop_source = $desktopSource
    onedrive_state = $oneDriveState
    onedrive_enabled = ($oneDriveRoots.Count -gt 0)
    canonical_development_checkout = $canonicalDev
    canonical_worktree_root = $worktreeRoot
    production_use_applicable = $productionApplicable
    production_use_path = $productionUse
    path_relation = $pathRelation
    canonical_entrypoint_authority = $entrypointAuthority
    canonical_entrypoint = $canonicalEntrypoint
    candidate_path = $currentCandidate
    candidate_classification = $candidateClassification
    path_disposition = $pathDisposition
    canonical_checkout_status = $checkoutStatus
    canonical_checkout_reparse_state = $canonicalReparseState
    canonical_checkout_head = $checkoutHead
    canonical_checkout_remote = $checkoutRemote
    current_directory_is_authority = $false
    next_action = if ($checkoutStatus -eq 'CANONICAL_PROVED') {
        "Set-Location -LiteralPath '$canonicalDev'"
    } elseif ($checkoutStatus -eq 'MISSING') {
        "MISSING: create or recover the one canonical checkout at '$canonicalDev'; do not create a fallback clone elsewhere."
    } else {
        "PRESERVE_AND_RECONCILE: '$canonicalDev' is not a proved canonical checkout ($checkoutStatus); inspect before mutation."
    }
    proof_ceiling = 'Local path/profile/checkout identity only; no remote freshness, production runtime currentness, entrypoint observation, or deployment proof.'
}

if ($AsJson) {
    $receipt | ConvertTo-Json -Depth 5
} else {
    Write-Host "Profile: $selectedProfileId"
    Write-Host "Desktop Known Folder: $desktop"
    Write-Host "Desktop Dev root: $desktopDev"
    Write-Host "OneDrive state: $oneDriveState"
    Write-Host "Canonical development: $canonicalDev"
    Write-Host "Canonical worktrees: $worktreeRoot"
    Write-Host "Production/use: $(if ($productionApplicable) { $productionUse } else { 'NOT_APPLICABLE' })"
    Write-Host "Path relation: $pathRelation"
    Write-Host "Entrypoint authority: $entrypointAuthority"
    Write-Host "Entrypoint: $(if ($null -ne $canonicalEntrypoint) { $canonicalEntrypoint } else { 'PROFILE_ROUTED' })"
    Write-Host "Observed candidate: $currentCandidate [$candidateClassification]"
    Write-Host "Disposition: $pathDisposition"
    Write-Host "Canonical checkout: $checkoutStatus [$canonicalReparseState]"
    Write-Host "Next: $($receipt.next_action)"
}

if ($RequireCheckout -and $checkoutStatus -ne 'CANONICAL_PROVED') {
    exit 3
}
exit 0
