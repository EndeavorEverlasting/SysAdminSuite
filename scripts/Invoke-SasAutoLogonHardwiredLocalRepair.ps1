#Requires -Version 5.1
<#
.SYNOPSIS
Repair the sealed AutoLogon runtime from an already-local exact commit on a hardwired protected network, then deploy.

.DESCRIPTION
This bounded field-repair lane exists for the case where repository acquisition already happened earlier,
the operator is now on a DomainAuthenticated non-Wi-Fi Northwell connection, and the current C:\SASAL
runtime must be repaired before deployment. It performs no Git command and no remote repository access.

The script proves the local source worktree is detached at the operator-supplied expected commit by reading
Git metadata as ordinary files, proves a DomainAuthenticated non-Wi-Fi interface before target work, rebuilds
C:\SASAL from the previously sealed tracked-file list plus this lane's explicitly declared new tracked files,
verifies SHA-256 parity with .NET, refreshes the installed sas shim, writes an explicit hardwired-local-repair
manifest, and then enters the existing crash-safe AutoLogon field transaction.

No target is contacted until the existing protected-network guard is established. Clinical-core packages are
never deployed by this lane.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedCommit,

    [string]$SourceRoot,
    [string]$RuntimeRoot = 'C:\SASAL',
    [switch]$ConfirmDeployment
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $ConfirmDeployment) {
    throw 'Explicit -ConfirmDeployment is required for hardwired local repair and deployment.'
}

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
} else {
    $SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
}
$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$ExpectedCommit = $ExpectedCommit.Trim().ToLowerInvariant()

if ($SourceRoot -notmatch '^[A-Za-z]:\\') {
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: source must be an already-local drive path, not UNC/network storage: $SourceRoot"
}
if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: existing sealed runtime is required: $RuntimeRoot"
}

function Get-SasSha256Hex {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $stream = $null
    $sha256 = $null
    try {
        $stream = [IO.File]::Open($LiteralPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha256 = [Security.Cryptography.SHA256]::Create()
        $bytes = $sha256.ComputeHash($stream)
        return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Resolve-SasDetachedHeadWithoutGit {
    param([Parameter(Mandatory = $true)][string]$Root)
    $dotGit = Join-Path $Root '.git'
    $gitDir = $null
    if (Test-Path -LiteralPath $dotGit -PathType Leaf) {
        $pointer = (Get-Content -LiteralPath $dotGit -Raw -Encoding UTF8).Trim()
        if ($pointer -notmatch '^gitdir:\s*(.+)$') {
            throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: unsupported .git pointer format: $dotGit"
        }
        $candidate = $Matches[1].Trim()
        if (-not [IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $Root $candidate }
        $gitDir = [IO.Path]::GetFullPath($candidate)
    }
    elseif (Test-Path -LiteralPath $dotGit -PathType Container) {
        $gitDir = [IO.Path]::GetFullPath($dotGit)
    }
    else {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: source is not a Git worktree: $Root"
    }

    $headPath = Join-Path $gitDir 'HEAD'
    if (-not (Test-Path -LiteralPath $headPath -PathType Leaf)) {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: source Git HEAD metadata is missing: $headPath"
    }
    $head = (Get-Content -LiteralPath $headPath -Raw -Encoding ASCII).Trim()
    if ($head -match '^ref:\s+') {
        throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: source must be an isolated detached worktree at the exact expected commit.'
    }
    if ($head -notmatch '^[0-9a-fA-F]{40}$') {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: source HEAD is not a full commit id: $head"
    }
    return $head.ToLowerInvariant()
}

$sourceHead = Resolve-SasDetachedHeadWithoutGit -Root $SourceRoot
if ($sourceHead -ne $ExpectedCommit) {
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: source HEAD mismatch. Expected=$ExpectedCommit Source=$sourceHead"
}

$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$manifestPath = Join-Path $stateRoot 'autologon-short-runtime.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: previous sealed runtime manifest is missing: $manifestPath"
}
try { $previousManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: previous runtime manifest is unreadable: $($_.Exception.Message)" }

if ([string]$previousManifest.runtime_root -and
    -not ([IO.Path]::GetFullPath([string]$previousManifest.runtime_root)).TrimEnd('\').Equals($RuntimeRoot.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: previous manifest points at a different runtime root.'
}
if (-not [bool]$previousManifest.runtime_remotes_removed -or [bool]$previousManifest.protected_bootstrap_git_network_allowed) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: previous runtime does not prove remotes removed and protected Git network disabled.'
}
$previousEntries = @($previousManifest.tracked_file_hashes)
if ($previousEntries.Count -lt 1) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: previous manifest has no tracked-file list to bound the repair copy.'
}

# This lane is stacked directly on the sealed-runtime commit. Its only new tracked files are declared
# here so the repaired runtime content set can converge to the exact lane commit without enumerating Git.
$repairLaneAddedTrackedPaths = @(
    'Run-AutoLogonHardwiredLocalRepair.cmd',
    'scripts/Invoke-SasAutoLogonHardwiredLocalRepair.ps1',
    'Tests/survey/test_autologon_hardwired_local_repair_contracts.py',
    'docs/AUTOLOGON_HARDWIRED_LOCAL_REPAIR.md'
)
$copyPaths = @($previousEntries | ForEach-Object { ([string]$_.path).Replace('\','/').Trim() } | Where-Object { $_ })
foreach ($addedPath in $repairLaneAddedTrackedPaths) {
    $canonicalAddedPath = $addedPath.Replace('\','/')
    if ($copyPaths -notcontains $canonicalAddedPath) { $copyPaths += $canonicalAddedPath }
}
$copyPaths = @($copyPaths | Sort-Object -Unique)

$networkBootstrap = Join-Path $SourceRoot 'scripts\Enable-SasNorthwellVpnNetworkGuard.ps1'
$operatorInstaller = Join-Path $SourceRoot 'scripts\Install-SasPortableLauncher.ps1'
foreach ($required in @($networkBootstrap,$operatorInstaller)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required hardwired repair dependency is missing: $required" }
}

Write-Host 'PROVING HARDWIRED DOMAIN-AUTHENTICATED NORTHWELL POSTURE' -ForegroundColor Cyan
$authority = @(& $networkBootstrap -ConfirmVpnPosture) | Select-Object -Last 1
if ($null -eq $authority -or [string]$authority.classification -ne 'SAS_VPN_NETWORK_GUARD_READY') {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: DomainAuthenticated non-Wi-Fi authority was not established.'
}
if ([bool]$authority.target_contact_performed -or [bool]$authority.target_mutation_performed) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: network bootstrap violated the no-target-contact repair boundary.'
}
$authorityConfig = [string]$authority.config_path
if ([string]::IsNullOrWhiteSpace($authorityConfig) -or -not (Test-Path -LiteralPath $authorityConfig -PathType Leaf)) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: network authority config was not created.'
}
$env:SAS_NETWORK_GUARD_CONFIG = $authorityConfig

Write-Host ''
Write-Host 'LOCAL-ONLY HARDWIRED RUNTIME REPAIR - NO GIT COMMANDS' -ForegroundColor Cyan
Write-Host "Source:   $SourceRoot"
Write-Host "Runtime:  $RuntimeRoot"
Write-Host "Commit:   $ExpectedCommit"
Write-Host "Files:    $($copyPaths.Count)"

$runtimePrefix = $RuntimeRoot.TrimEnd('\') + '\'
$sourcePrefix = $SourceRoot.TrimEnd('\') + '\'
$newHashes = @()
$copied = 0
foreach ($relative in $copyPaths) {
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative)) {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: invalid tracked path in repair plan: '$relative'"
    }
    $relativeWindows = $relative.Replace('/','\')
    $sourcePath = [IO.Path]::GetFullPath((Join-Path $SourceRoot $relativeWindows))
    $runtimePath = [IO.Path]::GetFullPath((Join-Path $RuntimeRoot $relativeWindows))
    if (-not $sourcePath.StartsWith($sourcePrefix,[StringComparison]::OrdinalIgnoreCase) -or
        -not $runtimePath.StartsWith($runtimePrefix,[StringComparison]::OrdinalIgnoreCase)) {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: tracked path escapes a bounded local root: $relative"
    }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: exact source commit is missing tracked runtime file: $relative"
    }
    $destinationDirectory = Split-Path -Parent $runtimePath
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    Copy-Item -LiteralPath $sourcePath -Destination $runtimePath -Force
    $sourceHash = Get-SasSha256Hex -LiteralPath $sourcePath
    $runtimeHash = Get-SasSha256Hex -LiteralPath $runtimePath
    if ($sourceHash -ne $runtimeHash) {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: local copy hash mismatch: $relative"
    }
    $newHashes += [pscustomobject][ordered]@{ path=$relative; sha256=$runtimeHash }
    $copied++
}

$crashSafeScript = Join-Path $RuntimeRoot 'scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1'
if (-not (Test-Path -LiteralPath $crashSafeScript -PathType Leaf)) {
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: repaired runtime is missing crash-safe field runner: $crashSafeScript"
}

$LASTEXITCODE = 0
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $operatorInstaller
if ($LASTEXITCODE -ne 0) {
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: installed sas shim refresh failed with exit code $LASTEXITCODE"
}

$manifest = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-short-runtime/hardwired-repair-v1'
    runtime_root = $RuntimeRoot
    source_root = $SourceRoot
    prepared_commit = $ExpectedCommit
    prepared_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    preparation_network_classification = 'PROTECTED_NORTHWELL'
    preparation_network_label = 'DomainAuthenticated non-Wi-Fi local repair'
    preparation_git_transport = 'NONE'
    preparation_remote_git_performed = $false
    source_head_verified_without_git = $true
    runtime_content_commit = $ExpectedCommit
    runtime_git_metadata_ignored = $true
    runtime_git_transport = 'LOCAL_FILESYSTEM_ONLY'
    runtime_remotes_removed = $true
    protected_bootstrap_git_network_allowed = $false
    tracked_file_hash_algorithm = 'SHA256'
    tracked_file_count = $newHashes.Count
    tracked_file_hashes = $newHashes
    repair_lane_added_tracked_paths = $repairLaneAddedTrackedPaths
    local_copy_file_count = $copied
    target_contact_performed = $false
    target_mutation_performed = $false
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host ''
Write-Host 'PASS: HARDWIRED LOCAL RUNTIME REPAIR COMPLETE' -ForegroundColor Green
Write-Host "Runtime content commit: $ExpectedCommit"
Write-Host "Local files repaired and verified: $copied"
Write-Host 'Remote Git performed: NO' -ForegroundColor Green
Write-Host 'Target contact during repair: NO' -ForegroundColor Green

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($crashSafeScript,[ref]$tokens,[ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    $parseErrors | Format-List * | Out-Host
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: repaired crash-safe field runner failed the Windows PowerShell parser gate.'
}

$env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST = $ComputerName.Trim()
Write-Host ''
Write-Host 'STARTING EXISTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION' -ForegroundColor Green
$LASTEXITCODE = 0
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $crashSafeScript `
    -ComputerName $ComputerName -RepositoryRoot $RuntimeRoot -RepositoryHead $ExpectedCommit -ConfirmDeployment
exit [int]$LASTEXITCODE
