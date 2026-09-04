#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$MachineProfile,
    [string]$DesktopDevRoot,
    [string]$CandidatePath,
    [ValidateSet('LOCAL','CI','POWERSHELL_REMOTE','SSH_REMOTE','CONTAINER','VM','WSL')]
    [string]$ExecutionTargetOverride,
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

# Execution context is evidence, not path authority. A Windows process proves the runtime boundary,
# not whether the operator is local, remoted, in CI, or inside another isolation boundary.
$processPath = 'UNKNOWN'
try {
    $process = Get-Process -Id $PID -ErrorAction Stop
    if ($null -ne $process -and -not [string]::IsNullOrWhiteSpace([string]$process.Path)) {
        $processPath = [IO.Path]::GetFullPath([string]$process.Path)
    }
} catch { }
$runtimeBoundary = 'WINDOWS_NATIVE'
$terminalHost = [string]$Host.Name
$terminalApplication = 'UNKNOWN_NOT_PROBED'
$powershellEdition = if ($PSVersionTable.PSObject.Properties['PSEdition']) { [string]$PSVersionTable.PSEdition } else { 'Desktop' }
$powershellVersion = [string]$PSVersionTable.PSVersion
$executionTarget = 'UNKNOWN'
$executionContextStatus = 'WINDOWS_PROCESS_CONTEXT_PARTIAL'
$executionTargetSource = 'unprobed'
if (-not [string]::IsNullOrWhiteSpace($ExecutionTargetOverride)) {
    $executionTarget = $ExecutionTargetOverride
    $executionContextStatus = 'EXPLICIT_EXECUTION_TARGET'
    $executionTargetSource = 'explicit_invocation'
} elseif ([string]$env:GITHUB_ACTIONS -eq 'true') {
    $executionTarget = 'CI'
    $executionContextStatus = 'PROVED_WINDOWS_CI'
    $executionTargetSource = 'GITHUB_ACTIONS'
} elseif ($null -ne (Get-Variable -Name PSSenderInfo -Scope Global -ErrorAction SilentlyContinue)) {
    $executionTarget = 'POWERSHELL_REMOTE'
    $executionContextStatus = 'PROVED_POWERSHELL_REMOTE'
    $executionTargetSource = 'PSSenderInfo'
} elseif (-not [string]::IsNullOrWhiteSpace([string]$env:SSH_CONNECTION)) {
    $executionTarget = 'SSH_REMOTE'
    $executionContextStatus = 'PROVED_SSH_REMOTE'
    $executionTargetSource = 'SSH_CONNECTION'
}

$currentLocation = Get-Location
$currentLocationProvider = if ($null -ne $currentLocation.Provider) { [string]$currentLocation.Provider.Name } else { 'UNKNOWN' }
$currentWorkingDirectory = [string]$currentLocation.Path
$currentWorkingDirectoryFileSystem = $null
if ($currentLocationProvider -eq 'FileSystem') {
    try { $currentWorkingDirectoryFileSystem = [IO.Path]::GetFullPath([string]$currentLocation.Path) } catch { $currentWorkingDirectoryFileSystem = $null }
}

$user = if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) { [string]$env:USERNAME } else { [Environment]::UserName }
if ([string]::IsNullOrWhiteSpace($user)) { throw 'Unable to resolve current Windows user identity.' }

$desktopKnownFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
if ([string]::IsNullOrWhiteSpace($desktopKnownFolder)) {
    throw 'Windows Desktop Known Folder could not be resolved. Canonical development location is UNKNOWN; no fallback clone is authorized.'
}
try { $desktopKnownFolder = [IO.Path]::GetFullPath($desktopKnownFolder) } catch { throw "Windows Desktop Known Folder is invalid: $desktopKnownFolder" }

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
} else {
    $desktopDev = Join-Path $desktopKnownFolder 'Dev'
}

foreach ($root in $availableOneDriveRoots) {
    $prefix = $root.TrimEnd('\') + '\'
    if ($desktopKnownFolder.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or $desktopKnownFolder.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        $oneDriveState = 'TARGET_FOLDER_REDIRECTED'
        break
    }
}

$profileEvidenceConflict = $oneDriveState -eq 'ROOT_UNAVAILABLE' -or $oneDriveState -eq 'MULTIPLE_ROOTS'

$template = [string]$profile.canonical_development_checkout.template
if ($template -ne '{desktop_dev_root}\SysAdminSuite') {
    throw "Unsupported Windows canonical development template: $template"
}
$canonicalDev = [IO.Path]::GetFullPath((Join-Path $desktopDev 'SysAdminSuite'))

if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required to resolve the canonical worktree root.' }
$localStateRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'SysAdminSuite'))
$worktreeRoot = [IO.Path]::GetFullPath((Join-Path $localStateRoot 'worktrees'))
$syncCache = [IO.Path]::GetFullPath((Join-Path $localStateRoot 'sync-cache'))
$preferredFieldReady = [IO.Path]::GetFullPath((Join-Path $localStateRoot 'field-ready'))

$productionApplicable = [bool]$profile.production_use_path.applicable
$productionUse = $null
$productionUseState = 'NOT_APPLICABLE'
$productionUseStateEvidence = 'Selected profile has no production/use path.'
$productionReparseState = 'NOT_APPLICABLE'
if ($productionApplicable) {
    $productionUse = [Environment]::ExpandEnvironmentVariables([string]$profile.production_use_path.template)
    $productionUse = [IO.Path]::GetFullPath($productionUse)
    if (-not (Test-Path -LiteralPath $productionUse -PathType Container)) {
        $productionUseState = 'OFFLINE'
        $productionUseStateEvidence = 'Registered production/use path does not currently exist.'
        $productionReparseState = 'NOT_INSPECTED_MISSING'
    } else {
        $productionUseState = 'UNKNOWN'
        $productionUseStateEvidence = 'Registered production/use path exists, but this read-only resolver does not infer quiescence from existence or from an installed launcher.'
        try {
            $productionItem = Get-Item -LiteralPath $productionUse -Force
            $productionReparseState = if (($productionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { 'REPARSE_POINT_PRESENT' } else { 'NORMAL_DIRECTORY' }
        } catch {
            $productionReparseState = 'UNKNOWN'
        }
    }
}

$pathRelation = if (-not $productionApplicable) {
    'DEVELOPMENT_PROFILE_ONLY_PRODUCTION_NOT_APPLICABLE'
} elseif ($canonicalDev.TrimEnd('\').Equals($productionUse.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    'SAME_PHYSICAL_PATH_PRODUCTION_IMPACTING'
} else {
    'SEPARATE_EXPLICIT_SYNC_INSTALL_PROMOTION_REQUIRED'
}
$pathRelationEvidence = 'Normalized path comparison; reparse-point state will be reconciled after canonical checkout inspection.'

$entrypointAuthority = [string]$profile.real_operator_entrypoint.authority
$canonicalEntrypoint = $null
$entrypointProperty = $profile.real_operator_entrypoint.PSObject.Properties['production_runtime_entrypoint']
if ($null -ne $entrypointProperty -and -not [string]::IsNullOrWhiteSpace([string]$entrypointProperty.Value)) {
    $canonicalEntrypoint = [Environment]::ExpandEnvironmentVariables([string]$entrypointProperty.Value)
}
$productionUpdateAuthority = $null
$updateAuthorityProperty = $profile.real_operator_entrypoint.PSObject.Properties['production_update_authority']
if ($null -ne $updateAuthorityProperty -and -not [string]::IsNullOrWhiteSpace([string]$updateAuthorityProperty.Value)) {
    $productionUpdateAuthority = [string]$updateAuthorityProperty.Value
}
$productionUpdateBoundary = $null
$updateBoundaryProperty = $profile.real_operator_entrypoint.PSObject.Properties['production_update_boundary']
if ($null -ne $updateBoundaryProperty -and -not [string]::IsNullOrWhiteSpace([string]$updateBoundaryProperty.Value)) {
    $productionUpdateBoundary = [string]$updateBoundaryProperty.Value
}

$currentCandidate = $null
$candidateClassification = 'UNKNOWN'
$candidateLocationClass = 'UNKNOWN'
if (-not [string]::IsNullOrWhiteSpace($CandidatePath)) {
    try { $currentCandidate = [IO.Path]::GetFullPath($CandidatePath.Trim()) } catch { $currentCandidate = $null }
} elseif ($currentLocationProvider -eq 'FileSystem' -and $null -ne $currentWorkingDirectoryFileSystem) {
    $currentCandidate = $currentWorkingDirectoryFileSystem
} else {
    $candidateClassification = 'UNKNOWN_NON_FILESYSTEM_CURRENT_LOCATION'
}
if ($null -ne $currentCandidate) {
    if ($currentCandidate.Equals($canonicalDev, [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'CANONICAL_DEVELOPMENT'
        $candidateLocationClass = 'CLONE'
    } elseif ($productionApplicable -and $currentCandidate.Equals($productionUse, [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'PRODUCTION_USE'
        $candidateLocationClass = 'INSTALL'
    } elseif ($currentCandidate.Equals($syncCache, [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'UPDATER_SYNC_CACHE'
        $candidateLocationClass = 'CLONE'
    } elseif ($currentCandidate.Equals($preferredFieldReady, [StringComparison]::OrdinalIgnoreCase) -or
              $currentCandidate.StartsWith(($preferredFieldReady + '-'), [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'UPDATER_FIELD_READY_WORKTREE'
        $candidateLocationClass = 'WORKTREE'
    } elseif ($currentCandidate.StartsWith($worktreeRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'ISOLATED_WORKTREE'
        $candidateLocationClass = 'WORKTREE'
    } elseif ($currentCandidate.StartsWith(([IO.Path]::GetFullPath((Join-Path $localStateRoot 'closeout-entry-'))), [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'EPHEMERAL_ACQUISITION'
        $candidateLocationClass = 'CACHE'
    } elseif ($currentCandidate.StartsWith(([IO.Path]::GetFullPath((Join-Path $localStateRoot 'short-runtime-preservation'))).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'PRESERVED_RUNTIME_BACKUP'
        $candidateLocationClass = 'BACKUP'
    } elseif ($currentCandidate.StartsWith(([IO.Path]::GetFullPath((Join-Path $localStateRoot 'Evidence'))).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
              $currentCandidate.StartsWith(([IO.Path]::GetFullPath((Join-Path $localStateRoot 'field-runs'))).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $candidateClassification = 'RUNTIME_OUTPUT'
        $candidateLocationClass = 'OUTPUT'
    }
}

$checkoutStatus = if ($oneDriveState -eq 'MULTIPLE_ROOTS') {
    'CONFLICT_ONEDRIVE_MULTIPLE_ROOTS'
} elseif ($oneDriveState -eq 'ROOT_UNAVAILABLE') {
    'CONFLICT_ONEDRIVE_ROOT_UNAVAILABLE'
} else {
    'MISSING'
}
$checkoutHead = $null
$checkoutRemote = $null
$canonicalReparseState = 'NOT_INSPECTED_MISSING'
$canonicalGitIoHealth = 'NOT_RUN'
if (-not $profileEvidenceConflict -and (Test-Path -LiteralPath $canonicalDev -PathType Container)) {
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
                    $remoteText = ([string]$checkoutRemote).Trim().TrimEnd('/')
                    $allowedRemotes = @(
                        'https://github.com/EndeavorEverlasting/SysAdminSuite',
                        'https://github.com/EndeavorEverlasting/SysAdminSuite.git',
                        'git@github.com:EndeavorEverlasting/SysAdminSuite',
                        'git@github.com:EndeavorEverlasting/SysAdminSuite.git',
                        'ssh://git@github.com/EndeavorEverlasting/SysAdminSuite',
                        'ssh://git@github.com/EndeavorEverlasting/SysAdminSuite.git'
                    )
                    $remoteMatches = $remoteExit -eq 0 -and ($allowedRemotes -contains $remoteText)
                    if (-not $remoteMatches) {
                        $checkoutStatus = 'CONFLICT_WRONG_REPOSITORY'
                    } elseif ($headExit -ne 0 -or ([string]$checkoutHead).Trim() -notmatch '^[0-9a-fA-F]{40}$') {
                        $checkoutStatus = 'UNKNOWN_GIT_IDENTITY'
                    } else {
                        $previousErrorActionPreference = $ErrorActionPreference
                        try {
                            $ErrorActionPreference = 'Continue'
                            & git -C $canonicalDev status --porcelain=v1 --untracked-files=no --ignore-submodules=dirty 1>$null 2>$null
                            $gitIoExit = $LASTEXITCODE
                        }
                        finally {
                            $ErrorActionPreference = $previousErrorActionPreference
                        }
                        if ($gitIoExit -ne 0) {
                            $canonicalGitIoHealth = 'UNHEALTHY'
                            $checkoutStatus = 'CONFLICT_GIT_IO_UNHEALTHY'
                        } else {
                            $canonicalGitIoHealth = 'HEALTHY'
                            $checkoutStatus = 'CANONICAL_PROVED'
                            $checkoutHead = ([string]$checkoutHead).Trim().ToLowerInvariant()
                            $checkoutRemote = $remoteText
                        }
                    }
                }
            }
        }
    }
}

if ($productionApplicable -and (
    $canonicalReparseState -eq 'REPARSE_POINT_PRESENT' -or
    $productionReparseState -eq 'REPARSE_POINT_PRESENT' -or
    $productionReparseState -eq 'UNKNOWN')) {
    $pathRelation = 'UNKNOWN_REPARSE_POINT_RELATION'
    $pathRelationEvidence = "Physical relation is not trusted because canonical_reparse=$canonicalReparseState production_reparse=$productionReparseState."
} elseif ($pathRelation -eq 'SAME_PHYSICAL_PATH_PRODUCTION_IMPACTING') {
    $pathRelationEvidence = 'Canonical development and production/use normalize to the same path and neither observed path is an unresolved reparse point.'
} elseif ($productionApplicable) {
    $pathRelationEvidence = 'Canonical development and production/use normalize to different paths and neither observed path is an unresolved reparse point.'
} else {
    $pathRelationEvidence = 'Selected profile has no production/use path.'
}

$pathDisposition = if ($checkoutStatus -eq 'CANONICAL_PROVED' -and $candidateClassification -eq 'CANONICAL_DEVELOPMENT') {
    'CANONICAL + PROVED'
} elseif ($checkoutStatus -eq 'MISSING') {
    'MISSING'
} elseif ($checkoutStatus.StartsWith('CONFLICT', [StringComparison]::OrdinalIgnoreCase)) {
    'CONFLICT'
} elseif ($candidateLocationClass -in @('WORKTREE','CACHE','BACKUP','OUTPUT')) {
    'NONCANONICAL + PRESERVE'
} else {
    'UNKNOWN'
}

# Bounded known-location inventory only. Do not search arbitrary disks and do not declare anything
# disposable without proving it contains no unique, dirty, unpushed, or separately owned work.
$knownLocations = @()
$knownLocations += [pscustomobject][ordered]@{ path=$canonicalDev; class='CLONE'; role='CANONICAL_DEVELOPMENT'; exists=(Test-Path -LiteralPath $canonicalDev -PathType Container); disposition='PRESERVE' }
if ($productionApplicable) {
    $knownLocations += [pscustomobject][ordered]@{ path=$productionUse; class='INSTALL'; role='PRODUCTION_USE'; exists=(Test-Path -LiteralPath $productionUse -PathType Container); disposition='PRESERVE' }
}
$knownLocations += [pscustomobject][ordered]@{ path=$worktreeRoot; class='WORKTREE'; role='WORKTREE_ROOT'; exists=(Test-Path -LiteralPath $worktreeRoot -PathType Container); disposition='PRESERVE' }
$knownLocations += [pscustomobject][ordered]@{ path=$syncCache; class='CLONE'; role='UPDATER_SYNC_CACHE'; exists=(Test-Path -LiteralPath $syncCache -PathType Container); disposition='PRESERVE' }
if (Test-Path -LiteralPath $worktreeRoot -PathType Container) {
    foreach ($item in @(Get-ChildItem -LiteralPath $worktreeRoot -Directory -ErrorAction SilentlyContinue)) {
        $knownLocations += [pscustomobject][ordered]@{ path=$item.FullName; class='WORKTREE'; role='APPROVED_ISOLATED_WORKTREE'; exists=$true; disposition='PRESERVE_UNTIL_PROVED_DISPOSABLE' }
    }
}
if (Test-Path -LiteralPath $localStateRoot -PathType Container) {
    foreach ($item in @(Get-ChildItem -LiteralPath $localStateRoot -Directory -Filter 'field-ready*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'field-ready' -or $_.Name -like 'field-ready-*' })) {
        $knownLocations += [pscustomobject][ordered]@{ path=$item.FullName; class='WORKTREE'; role='UPDATER_FIELD_READY_WORKTREE'; exists=$true; disposition='PRESERVE_UNTIL_PROVED_DISPOSABLE' }
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $localStateRoot -Directory -Filter 'closeout-entry-*' -ErrorAction SilentlyContinue)) {
        $knownLocations += [pscustomobject][ordered]@{ path=$item.FullName; class='CACHE'; role='EPHEMERAL_ACQUISITION'; exists=$true; disposition='PRESERVE_UNTIL_PROVED_DISPOSABLE' }
    }
    $preservationRoot = Join-Path $localStateRoot 'short-runtime-preservation'
    if (Test-Path -LiteralPath $preservationRoot -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $preservationRoot -Directory -ErrorAction SilentlyContinue)) {
            $knownLocations += [pscustomobject][ordered]@{ path=$item.FullName; class='BACKUP'; role='PRESERVED_RUNTIME'; exists=$true; disposition='PRESERVE' }
        }
    }
    foreach ($outputName in @('Evidence','field-runs')) {
        $outputRoot = Join-Path $localStateRoot $outputName
        if (Test-Path -LiteralPath $outputRoot -PathType Container) {
            $knownLocations += [pscustomobject][ordered]@{ path=$outputRoot; class='OUTPUT'; role='RUNTIME_OUTPUT_ROOT'; exists=$true; disposition='PRESERVE' }
        }
    }
}

$productionAdHocMutationAllowed = $false
$developmentMutationGuard = if ($pathRelation -eq 'UNKNOWN_REPARSE_POINT_RELATION') {
    'BLOCK_UNTIL_PHYSICAL_PATH_RELATION_PROVED'
} elseif ($pathRelation -eq 'SAME_PHYSICAL_PATH_PRODUCTION_IMPACTING' -and $productionUseState -in @('ACTIVE','UNKNOWN')) {
    'BLOCK_UNTIL_PRODUCTION_QUIESCED_OR_TRACKED_IN_PLACE_SAFETY_PROVED'
} elseif ($pathRelation -eq 'SAME_PHYSICAL_PATH_PRODUCTION_IMPACTING') {
    'PRODUCTION_IMPACTING_USE_TRACKED_BOUNDARY'
} else {
    'CANONICAL_DEVELOPMENT_OR_APPROVED_WORKTREE_ONLY'
}

$receipt = [ordered]@{
    schema_version = 'sas-canonical-path-input-receipt/v1'
    repository = 'EndeavorEverlasting/SysAdminSuite'
    selected_profile = $selectedProfileId
    execution_context_status = $executionContextStatus
    execution_target_source = $executionTargetSource
    terminal_host = $terminalHost
    terminal_application = $terminalApplication
    shell_interpreter = $processPath
    powershell_edition = $powershellEdition
    powershell_version = $powershellVersion
    runtime_boundary = $runtimeBoundary
    execution_target = $executionTarget
    current_location_provider = $currentLocationProvider
    current_working_directory = $currentWorkingDirectory
    current_working_directory_filesystem = $currentWorkingDirectoryFileSystem
    os = 'windows'
    path_semantics = 'WINDOWS_CASE_INSENSITIVE_NORMALIZED_FULL_PATH'
    user = $user
    desktop_known_folder = $desktopKnownFolder
    desktop_dev_root = $desktopDev
    desktop_source = $desktopSource
    onedrive_state = $oneDriveState
    onedrive_enabled = ($oneDriveRoots.Count -gt 0)
    profile_evidence_conflict = $profileEvidenceConflict
    canonical_development_checkout = $canonicalDev
    canonical_worktree_root = $worktreeRoot
    production_use_applicable = $productionApplicable
    production_use_path = $productionUse
    production_use_state = $productionUseState
    production_use_state_evidence = $productionUseStateEvidence
    production_use_reparse_state = $productionReparseState
    production_ad_hoc_mutation_allowed = $productionAdHocMutationAllowed
    production_update_authority = $productionUpdateAuthority
    production_update_boundary = $productionUpdateBoundary
    development_mutation_guard = $developmentMutationGuard
    path_relation = $pathRelation
    path_relation_evidence = $pathRelationEvidence
    canonical_entrypoint_authority = $entrypointAuthority
    canonical_entrypoint = $canonicalEntrypoint
    candidate_path = $currentCandidate
    candidate_classification = $candidateClassification
    candidate_location_class = $candidateLocationClass
    location_class_vocabulary = @('CLONE','WORKTREE','INSTALL','MIRROR','CACHE','OUTPUT','BACKUP','UNKNOWN')
    known_location_inventory = $knownLocations
    cleanup_authorized = $false
    path_disposition = $pathDisposition
    canonical_checkout_status = $checkoutStatus
    canonical_checkout_reparse_state = $canonicalReparseState
    canonical_git_io_health = $canonicalGitIoHealth
    canonical_checkout_head = $checkoutHead
    canonical_checkout_remote = $checkoutRemote
    current_directory_is_authority = $false
    remote_integration_is_local_deployment = $false
    next_action = if ($checkoutStatus -eq 'CANONICAL_PROVED') {
        "Set-Location -LiteralPath '$canonicalDev'"
    } elseif ($checkoutStatus -eq 'MISSING') {
        "MISSING: create or recover the one canonical checkout at '$canonicalDev'; do not create a fallback clone elsewhere."
    } elseif ($checkoutStatus -eq 'CONFLICT_GIT_IO_UNHEALTHY') {
        "PRESERVE_AND_RECONCILE: Git cannot safely read the canonical checkout at '$canonicalDev'; inventory and repair/hydrate that checkout before fetch, status, log, worktree creation, or cleanup."
    } elseif ($profileEvidenceConflict) {
        "PRESERVE_AND_RECONCILE: OneDrive profile evidence is $oneDriveState; resolve the conflicting/unavailable roots before trusting '$canonicalDev'."
    } else {
        "PRESERVE_AND_RECONCILE: '$canonicalDev' is not a proved canonical checkout ($checkoutStatus); inspect before mutation."
    }
    proof_ceiling = 'Local execution-context, path/profile/checkout identity, bounded known-copy inventory, Git I/O health, and conservative production-use state only; no remote freshness, production runtime currentness, entrypoint observation, quiescence, or deployment proof.'
}

if ($AsJson) {
    $receipt | ConvertTo-Json -Depth 7
} else {
    Write-Host "Execution: $executionContextStatus [$powershellEdition $powershellVersion] $processPath"
    Write-Host "Execution target: $executionTarget ($executionTargetSource) / $runtimeBoundary"
    Write-Host "Current location: $currentLocationProvider :: $currentWorkingDirectory"
    Write-Host "Profile: $selectedProfileId"
    Write-Host "Desktop Known Folder: $desktopKnownFolder"
    Write-Host "Desktop Dev root: $desktopDev"
    Write-Host "OneDrive state: $oneDriveState"
    Write-Host "Canonical development: $canonicalDev"
    Write-Host "Canonical worktrees: $worktreeRoot"
    Write-Host "Production/use: $(if ($productionApplicable) { $productionUse } else { 'NOT_APPLICABLE' })"
    Write-Host "PROD_USE_STATE: $productionUseState"
    Write-Host "Production ad-hoc mutation: BLOCKED"
    Write-Host "Production update authority: $(if ($productionUpdateAuthority) { $productionUpdateAuthority } else { 'NOT_APPLICABLE' })"
    Write-Host "Path relation: $pathRelation"
    Write-Host "Path relation evidence: $pathRelationEvidence"
    Write-Host "Entrypoint authority: $entrypointAuthority"
    Write-Host "Entrypoint: $(if ($null -ne $canonicalEntrypoint) { $canonicalEntrypoint } else { 'PROFILE_ROUTED' })"
    Write-Host "Observed candidate: $(if ($null -ne $currentCandidate) { $currentCandidate } else { 'NON_FILESYSTEM_OR_INVALID' }) [$candidateClassification / $candidateLocationClass]"
    Write-Host "Disposition: $pathDisposition"
    Write-Host "Canonical checkout: $checkoutStatus [$canonicalReparseState]"
    Write-Host "Git I/O health: $canonicalGitIoHealth"
    Write-Host "Known locations inventoried: $($knownLocations.Count); cleanup authorized: NO"
    Write-Host "Next: $($receipt.next_action)"
}

if ($RequireCheckout -and $checkoutStatus -ne 'CANONICAL_PROVED') {
    exit 3
}
exit 0
