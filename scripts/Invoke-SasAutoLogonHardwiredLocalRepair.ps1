#Requires -Version 5.1
<#
.SYNOPSIS
Reseal C:\SASAL from an exact already-local SysAdminSuite checkout on protected hardwire, then deploy AutoLogon.

.DESCRIPTION
This lane exists for an Admin Box that is already on an approved DomainAuthenticated non-Wi-Fi Northwell
connection and already has the exact approved SysAdminSuite commit in a clean local checkout. It performs no
remote repository acquisition. Local Git is used only to prove the source checkout, transfer that exact commit
from the local source path into the existing sealed C:\SASAL repository, verify the complete tracked tree, and
remove runtime remotes before the existing crash-safe AutoLogon transaction starts.

Ordinary `sas refresh` remains Guest/Internet-only. This script does not make GitHub, origin, pull, clone, or
remote fetch legal on the protected network. It fails closed unless the prior runtime proves remotes removed,
the source and runtime are clean, the source is exactly ExpectedCommit, and the current network has an active
DomainAuthenticated non-Wi-Fi authority. No target is contacted before those gates complete.
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

    [switch]$ConfirmDeployment
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_CONFIG_NOSYSTEM = '1'

if (-not $ConfirmDeployment) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: explicit -ConfirmDeployment is required.'
}

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
else {
    $SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
}
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$ExpectedCommit = $ExpectedCommit.Trim().ToLowerInvariant()
$RuntimeRoot = 'C:\SASAL'
$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)

if ($SourceRoot -notmatch '^[A-Za-z]:\\') {
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: source must be an already-local drive path, not UNC/network storage: $SourceRoot"
}
if ($SourceRoot.TrimEnd('\').Equals($RuntimeRoot.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: source checkout and sealed runtime must be different local roots.'
}
if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: existing sealed runtime is required: $RuntimeRoot"
}

function Resolve-SasGitExecutable {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { $command = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return [IO.Path]::GetFullPath([string]$command.Source)
    }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path $env:ProgramFiles 'Git\bin\git.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: Git for Windows is required for local-only repository transfer.'
}

$script:SasGitExe = Resolve-SasGitExecutable

function Invoke-SasHardwiredLocalGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage,
        [switch]$Quiet
    )

    $verb = if ($Arguments.Count -gt 0) { [string]$Arguments[0] } else { '' }
    if ($verb -notin @('rev-parse','status','ls-files','fetch','checkout','remote')) {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: local Git verb is not allowlisted: $verb"
    }
    if ($verb -eq 'fetch') {
        if ($Arguments.Count -lt 5 -or [string]$Arguments[4] -ne $SourceRoot) {
            throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: hardwired Git fetch must name the already-local SourceRoot explicitly.'
        }
        if ([string]$Arguments[-1] -ne $ExpectedCommit) {
            throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: hardwired local fetch must request the exact expected commit.'
        }
    }

    $stderrPath = Join-Path $env:TEMP ('sas-hardwired-local-git-' + [guid]::NewGuid().ToString('N') + '.err')
    $previousPreference = $ErrorActionPreference
    $stdout = @()
    $exitCode = 0
    try {
        $ErrorActionPreference = 'Continue'
        $stdout = @(& $script:SasGitExe -C $Root @Arguments 2> $stderrPath)
        $exitCode = [int]$global:LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $stderr = ''
    if (Test-Path -LiteralPath $stderrPath) {
        try {
            $raw = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
            if ($null -ne $raw) { $stderr = ([string]$raw).Trim() }
        }
        finally { Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue }
    }
    $stdoutLines = @($stdout | ForEach-Object { [string]$_ })
    $stdoutText = ($stdoutLines -join [Environment]::NewLine).Trim()
    if ($exitCode -ne 0) {
        $detail = @($stdoutText,$stderr | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = '(git produced no diagnostic text)' }
        throw "$FailureMessage (git exit $exitCode)`n$detail"
    }
    if (-not $Quiet) {
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) { Write-Host $stdoutText }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Host $stderr -ForegroundColor DarkGray }
    }
    return @($stdoutLines)
}

function Get-SasHardwiredGitScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    $lines = @(Invoke-SasHardwiredLocalGit -Root $Root -Arguments $Arguments -FailureMessage $FailureMessage -Quiet)
    $value = [string]($lines | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$FailureMessage (empty git output)" }
    return $value.Trim()
}

function Get-SasSha256Hex {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $stream = $null
    $sha256 = $null
    try {
        $stream = [IO.File]::Open($LiteralPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha256 = [Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Write-SasUtf8Json {
    param([Parameter(Mandatory = $true)][string]$Path,[Parameter(Mandatory = $true)]$Value)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $json = $Value | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($Path,$json,(New-Object Text.UTF8Encoding($false)))
}

Write-Host 'VERIFYING EXACT ALREADY-LOCAL SOURCE CHECKOUT' -ForegroundColor Cyan
$sourceInside = Get-SasHardwiredGitScalar -Root $SourceRoot -Arguments @('rev-parse','--is-inside-work-tree') -FailureMessage 'Source is not a usable local Git worktree.'
if ($sourceInside -ne 'true') { throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: source is not a Git worktree: $SourceRoot" }
$sourceHead = (Get-SasHardwiredGitScalar -Root $SourceRoot -Arguments @('rev-parse','HEAD') -FailureMessage 'Could not resolve local source HEAD.').ToLowerInvariant()
if ($sourceHead -ne $ExpectedCommit) {
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: local source HEAD mismatch. Expected=$ExpectedCommit Source=$sourceHead"
}
$sourceDirty = @(Invoke-SasHardwiredLocalGit -Root $SourceRoot -Arguments @('status','--porcelain') -FailureMessage 'Could not inspect local source state.' -Quiet)
if (@($sourceDirty | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
    $sourceDirty | Out-Host
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: local source checkout is dirty; no runtime mutation was started: $SourceRoot"
}
$sourceTracked = @(Invoke-SasHardwiredLocalGit -Root $SourceRoot -Arguments @('ls-files') -FailureMessage 'Could not enumerate exact local source tracked files.' -Quiet | ForEach-Object { ([string]$_).Trim().Replace('\','/') } | Where-Object { $_ } | Sort-Object -Unique)
if ($sourceTracked.Count -lt 1) { throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: exact local source returned no tracked files.' }
Write-Host "PASS: exact local source checkout is clean at $sourceHead ($($sourceTracked.Count) tracked files)." -ForegroundColor Green

$runtimeGitMetadata = Join-Path $RuntimeRoot '.git'
$runtimeManifestPath = Join-Path $runtimeGitMetadata 'sas-autologon-short-runtime.json'
$currentManifestPath = Join-Path (Join-Path $env:LOCALAPPDATA 'SysAdminSuite') 'autologon-short-runtime.json'
$priorManifestPath = if (Test-Path -LiteralPath $runtimeManifestPath -PathType Leaf) { $runtimeManifestPath } elseif (Test-Path -LiteralPath $currentManifestPath -PathType Leaf) { $currentManifestPath } else { $null }
if ($null -eq $priorManifestPath) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: a prior sealed AutoLogon v2 manifest is required before protected-network local repair.'
}
try { $prior = Get-Content -LiteralPath $priorManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: prior runtime manifest is unreadable: $($_.Exception.Message)" }
if ([string]$prior.schema_version -ne 'sas-autologon-short-runtime/v2' -or
    -not [bool]$prior.runtime_remotes_removed -or
    [bool]$prior.protected_bootstrap_git_network_allowed) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: prior runtime does not prove v2 seal, remotes removed, and protected Git network disabled.'
}
if (-not (Test-Path -LiteralPath $runtimeGitMetadata -PathType Container)) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: C:\SASAL must be the standalone sealed runtime with a local .git metadata directory.'
}

$networkBootstrap = Join-Path $SourceRoot 'scripts\Enable-SasNorthwellVpnNetworkGuard.ps1'
if (-not (Test-Path -LiteralPath $networkBootstrap -PathType Leaf)) {
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: network authority bootstrap missing from exact source: $networkBootstrap"
}
Write-Host ''
Write-Host 'PROVING DOMAIN-AUTHENTICATED NON-WIFI NORTHWELL AUTHORITY' -ForegroundColor Cyan
$authority = @(& $networkBootstrap -ConfirmVpnPosture) | Select-Object -Last 1
if ($null -eq $authority -or [string]$authority.classification -ne 'SAS_VPN_NETWORK_GUARD_READY') {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: DomainAuthenticated non-Wi-Fi Northwell authority was not established.'
}
if ([bool]$authority.target_contact_performed -or [bool]$authority.target_mutation_performed) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: network authority bootstrap violated the no-target-contact preparation boundary.'
}
$authorityConfig = [string]$authority.config_path
if ([string]::IsNullOrWhiteSpace($authorityConfig) -or -not (Test-Path -LiteralPath $authorityConfig -PathType Leaf)) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: exact local network authority config was not created.'
}
$env:SAS_NETWORK_GUARD_CONFIG = $authorityConfig

Write-Host ''
Write-Host 'LOCAL-ONLY HARDWIRED RUNTIME RESEAL - REMOTE REPOSITORY I/O DISABLED' -ForegroundColor Cyan
$runtimeInside = Get-SasHardwiredGitScalar -Root $RuntimeRoot -Arguments @('rev-parse','--is-inside-work-tree') -FailureMessage 'C:\SASAL is not a usable Git worktree.'
if ($runtimeInside -ne 'true') { throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: C:\SASAL is not a usable Git worktree.' }
$runtimeDirty = @(Invoke-SasHardwiredLocalGit -Root $RuntimeRoot -Arguments @('status','--porcelain') -FailureMessage 'Could not inspect sealed runtime state.' -Quiet)
if (@($runtimeDirty | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
    $runtimeDirty | Out-Host
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: C:\SASAL contains local work. Nothing was reset, cleaned, or overwritten.'
}

[void](Invoke-SasHardwiredLocalGit -Root $RuntimeRoot -Arguments @('fetch','--no-tags','--no-write-fetch-head',$SourceRoot,$ExpectedCommit) -FailureMessage 'Local-only object transfer from the exact source checkout failed.')
[void](Invoke-SasHardwiredLocalGit -Root $RuntimeRoot -Arguments @('checkout','--detach',$ExpectedCommit) -FailureMessage 'Could not pin C:\SASAL to the exact locally available commit.')
$runtimeHead = (Get-SasHardwiredGitScalar -Root $RuntimeRoot -Arguments @('rev-parse','HEAD') -FailureMessage 'Could not verify hardwired runtime HEAD.').ToLowerInvariant()
if ($runtimeHead -ne $ExpectedCommit) { throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: runtime HEAD mismatch. Expected=$ExpectedCommit Runtime=$runtimeHead" }
$runtimeDirtyAfter = @(Invoke-SasHardwiredLocalGit -Root $RuntimeRoot -Arguments @('status','--porcelain') -FailureMessage 'Could not verify final hardwired runtime state.' -Quiet)
if (@($runtimeDirtyAfter | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: runtime became dirty during local-only convergence.'
}

$remotes = @(Invoke-SasHardwiredLocalGit -Root $RuntimeRoot -Arguments @('remote') -FailureMessage 'Could not inspect runtime remotes.' -Quiet)
foreach ($remote in @($remotes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
    [void](Invoke-SasHardwiredLocalGit -Root $RuntimeRoot -Arguments @('remote','remove',[string]$remote) -FailureMessage "Could not remove runtime remote '$remote'.")
}
$remainingRemotes = @(Invoke-SasHardwiredLocalGit -Root $RuntimeRoot -Arguments @('remote') -FailureMessage 'Could not verify runtime remotes after local reseal.' -Quiet)
if (@($remainingRemotes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: C:\SASAL still has a Git remote after local-only reseal.'
}

$runtimeTracked = @(Invoke-SasHardwiredLocalGit -Root $RuntimeRoot -Arguments @('ls-files') -FailureMessage 'Could not enumerate resealed runtime tracked files.' -Quiet | ForEach-Object { ([string]$_).Trim().Replace('\','/') } | Where-Object { $_ } | Sort-Object -Unique)
$trackedDelta = @(Compare-Object -ReferenceObject $sourceTracked -DifferenceObject $runtimeTracked)
if ($trackedDelta.Count -gt 0) {
    $trackedDelta | Format-Table -AutoSize | Out-Host
    throw 'HARDWIRED_LOCAL_REPAIR_BLOCKED: source/runtime tracked-file sets differ after exact local transfer.'
}

$runtimePrefix = $RuntimeRoot.TrimEnd('\') + '\'
$hashes = @()
foreach ($relative in $runtimeTracked) {
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative)) {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: invalid tracked path: '$relative'"
    }
    $fullPath = [IO.Path]::GetFullPath((Join-Path $RuntimeRoot $relative.Replace('/','\')))
    if (-not $fullPath.StartsWith($runtimePrefix,[StringComparison]::OrdinalIgnoreCase)) {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: tracked path escapes C:\SASAL: $relative"
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: tracked runtime file missing after local transfer: $relative"
    }
    $hashes += [pscustomobject][ordered]@{ path=$relative; sha256=(Get-SasSha256Hex -LiteralPath $fullPath) }
}

$manifest = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-short-runtime/v2'
    runtime_root = $RuntimeRoot
    source_root = $SourceRoot
    prepared_commit = $ExpectedCommit
    prepared_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    preparation_network_classification = 'PROTECTED_NORTHWELL'
    preparation_network_label = 'DomainAuthenticated non-Wi-Fi hardwired local reseal'
    preparation_mode = 'HARDWIRED_LOCAL_RESEAL'
    preparation_git_transport = 'LOCAL_FILESYSTEM_ONLY'
    preparation_remote_git_performed = $false
    runtime_git_transport = 'LOCAL_FILESYSTEM_ONLY'
    runtime_remotes_removed = $true
    protected_bootstrap_git_network_allowed = $false
    tracked_file_hash_algorithm = 'SHA256'
    tracked_file_count = $hashes.Count
    tracked_file_hashes = $hashes
    target_contact_performed = $false
    target_mutation_performed = $false
}
Write-SasUtf8Json -Path $runtimeManifestPath -Value $manifest
Write-SasUtf8Json -Path $currentManifestPath -Value $manifest

foreach ($entry in $hashes) {
    $fullPath = [IO.Path]::GetFullPath((Join-Path $RuntimeRoot ([string]$entry.path).Replace('/','\')))
    $actual = Get-SasSha256Hex -LiteralPath $fullPath
    if ($actual -ne [string]$entry.sha256) {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: post-seal SHA-256 mismatch: $($entry.path)"
    }
}

$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$receiptPath = Join-Path $stateRoot 'autologon-hardwired-local-reseal.json'
$receipt = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-hardwired-local-reseal/v1'
    created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    status = 'READY_FOR_CRASH_SAFE_AUTOLOGON'
    source_root = $SourceRoot
    runtime_root = $RuntimeRoot
    prepared_commit = $ExpectedCommit
    tracked_file_count = $hashes.Count
    preparation_network_classification = 'PROTECTED_NORTHWELL'
    preparation_mode = 'HARDWIRED_LOCAL_RESEAL'
    preparation_git_transport = 'LOCAL_FILESYSTEM_ONLY'
    preparation_remote_git_performed = $false
    runtime_remotes_removed = $true
    target_contact_performed = $false
    target_mutation_performed = $false
}
Write-SasUtf8Json -Path $receiptPath -Value $receipt

$operatorInstaller = Join-Path $RuntimeRoot 'scripts\Install-SasPortableLauncher.ps1'
$crashSafeScript = Join-Path $RuntimeRoot 'scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1'
foreach ($required in @($operatorInstaller,$crashSafeScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: resealed runtime dependency missing: $required"
    }
}

$LASTEXITCODE = 0
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $operatorInstaller
if ([int]$LASTEXITCODE -ne 0) {
    throw "HARDWIRED_LOCAL_REPAIR_BLOCKED: installed sas shim refresh failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'PASS: HARDWIRED LOCAL RUNTIME RESEAL COMPLETE' -ForegroundColor Green
Write-Host "Runtime commit: $ExpectedCommit"
Write-Host "Tracked files sealed: $($hashes.Count)"
Write-Host 'Remote repository acquisition: NONE' -ForegroundColor Green
Write-Host 'Runtime Git remotes: NONE' -ForegroundColor Green
Write-Host 'Target contact during reseal: NONE' -ForegroundColor Green
Write-Host "Receipt: $receiptPath"

Write-Host ''
Write-Host 'STARTING EXISTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION' -ForegroundColor Green
$LASTEXITCODE = 0
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $crashSafeScript `
    -ComputerName $ComputerName -RepositoryRoot $RuntimeRoot -RepositoryHead $ExpectedCommit -ConfirmDeployment
$deploymentExit = [int]$LASTEXITCODE
if ($deploymentExit -ne 0) {
    Write-Host "HARDWIRED_AUTOLOGON_FAILED: crash-safe deployment returned exit code $deploymentExit. Preserved evidence is authoritative; do not blindly rerun." -ForegroundColor Yellow
    exit $deploymentExit
}

Write-Host 'HARDWIRED_AUTOLOGON_TRANSACTION_RETURNED_SUCCESS' -ForegroundColor Green
exit 0
