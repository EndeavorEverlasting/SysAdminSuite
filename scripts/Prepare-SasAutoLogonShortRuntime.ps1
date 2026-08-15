#Requires -Version 5.1
<#
.SYNOPSIS
Stage the short AutoLogon runtime from an already-refreshed local checkout.

.DESCRIPTION
This script is intentionally local-only. It never names or contacts GitHub and never contacts a field target.
It must run while the operator is on Guest/Internet, copies the exact already-fetched commit into C:\SASAL
through local Git object transfer, removes runtime remotes so protected-network code cannot accidentally fetch,
and writes a local preparation manifest consumed by the protected AutoLogon bootstrap.

Existing dirty runtime content is never reset, cleaned, removed, or overwritten.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceRoot,

    [string]$RuntimeRoot = 'C:\SASAL',

    [string]$ExpectedCommit
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$statePath = Join-Path $stateRoot 'autologon-short-runtime.json'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Resolve-SasGitExecutable {
    foreach ($candidate in @(
        (Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path $env:ProgramFiles 'Git\bin\git.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath([string]$candidate)
        }
    }
    throw 'Git for Windows could not be resolved for local runtime staging.'
}

$script:SasGitExe = Resolve-SasGitExecutable

function Invoke-SasLocalGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage,
        [switch]$Quiet
    )

    $stderrPath = Join-Path $env:TEMP ('sas-local-git-' + [guid]::NewGuid().ToString('N') + '.err')
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $LASTEXITCODE = 0
        $stdout = @(& $script:SasGitExe -C $Root @Arguments 2> $stderrPath)
        $exitCode = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $stderr = if (Test-Path -LiteralPath $stderrPath) {
        try { (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue).Trim() }
        finally { Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue }
    } else { '' }
    $stdoutText = (@($stdout | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()

    if ($exitCode -ne 0) {
        $detail = @($stdoutText,$stderr | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = '(git produced no diagnostic text)' }
        throw "$FailureMessage (git exit $exitCode)`n$detail"
    }
    if (-not $Quiet) {
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) { Write-Host $stdoutText }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Host $stderr -ForegroundColor DarkGray }
    }
    return @($stdout | ForEach-Object { [string]$_ })
}

function Get-SasLocalGitScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    $lines = @(Invoke-SasLocalGit -Root $Root -Arguments $Arguments -FailureMessage $FailureMessage -Quiet)
    $value = [string]($lines | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$FailureMessage (empty git output)" }
    return $value.Trim()
}

$networkModule = Join-Path $SourceRoot 'scripts\SasOperatorSession.psm1'
if (-not (Test-Path -LiteralPath $networkModule -PathType Leaf)) {
    throw "Operator network module missing from source runtime: $networkModule"
}
Import-Module $networkModule -Force
$currentNetwork = Get-SasOperatorNetworkClassification -RepoRoot $SourceRoot
if ([string]$currentNetwork.classification -ne 'GUEST_INTERNET') {
    throw "AUTOLOGON_RUNTIME_STAGE_BLOCKED: runtime preparation is Guest/Internet only. Current classification: $($currentNetwork.classification); label: $($currentNetwork.label)"
}

$sourceHead = Get-SasLocalGitScalar -Root $SourceRoot -Arguments @('rev-parse','HEAD') -FailureMessage 'Could not resolve source runtime HEAD.'
if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and $sourceHead -ne $ExpectedCommit.Trim()) {
    throw "Source runtime HEAD mismatch. Expected $($ExpectedCommit.Trim()); got $sourceHead."
}
$sourceDirty = @(Invoke-SasLocalGit -Root $SourceRoot -Arguments @('status','--porcelain') -FailureMessage 'Could not inspect source runtime state.' -Quiet)
if (@($sourceDirty | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
    throw "Source runtime is dirty and cannot be sealed for field deployment: $SourceRoot"
}

if (-not (Test-Path -LiteralPath $RuntimeRoot)) {
    New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null
    [void](Invoke-SasLocalGit -Root $RuntimeRoot -Arguments @('init') -FailureMessage "Could not initialize short runtime: $RuntimeRoot")
} elseif (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
    throw "Short runtime path exists but is not a directory: $RuntimeRoot"
}

$inside = Get-SasLocalGitScalar -Root $RuntimeRoot -Arguments @('rev-parse','--is-inside-work-tree') -FailureMessage "Short runtime is not a usable Git worktree: $RuntimeRoot"
if ($inside -ne 'true') { throw "Short runtime is not a Git worktree: $RuntimeRoot" }

$runtimeDirty = @(Invoke-SasLocalGit -Root $RuntimeRoot -Arguments @('status','--porcelain') -FailureMessage 'Could not inspect short runtime state.' -Quiet)
if (@($runtimeDirty | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
    throw "Short runtime contains local work. Nothing was reset or cleaned: $RuntimeRoot"
}

Write-Host 'LOCAL-ONLY AUTOLOGON RUNTIME STAGING' -ForegroundColor Cyan
Write-Host "Source:  $SourceRoot"
Write-Host "Runtime: $RuntimeRoot"
Write-Host "Commit:  $sourceHead"
Write-Host 'Git transport: local filesystem only' -ForegroundColor Green

[void](Invoke-SasLocalGit -Root $RuntimeRoot -Arguments @('fetch','--no-tags','--no-write-fetch-head',$SourceRoot,$sourceHead) -FailureMessage 'Local object transfer into the short runtime failed.')
[void](Invoke-SasLocalGit -Root $RuntimeRoot -Arguments @('checkout','--detach',$sourceHead) -FailureMessage 'Could not pin the short runtime to the prepared commit.')

$runtimeHead = Get-SasLocalGitScalar -Root $RuntimeRoot -Arguments @('rev-parse','HEAD') -FailureMessage 'Could not verify short runtime HEAD.'
if ($runtimeHead -ne $sourceHead) { throw "Short runtime HEAD mismatch. Expected $sourceHead; got $runtimeHead." }

$runtimeDirtyAfter = @(Invoke-SasLocalGit -Root $RuntimeRoot -Arguments @('status','--porcelain') -FailureMessage 'Could not verify final short runtime state.' -Quiet)
if (@($runtimeDirtyAfter | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
    throw 'Short runtime became dirty during local staging; refusing to seal it.'
}

$remotes = @(Invoke-SasLocalGit -Root $RuntimeRoot -Arguments @('remote') -FailureMessage 'Could not inspect short runtime remotes.' -Quiet)
foreach ($remote in @($remotes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
    [void](Invoke-SasLocalGit -Root $RuntimeRoot -Arguments @('remote','remove',[string]$remote) -FailureMessage "Could not remove short-runtime remote '$remote'.")
}
$remainingRemotes = @(Invoke-SasLocalGit -Root $RuntimeRoot -Arguments @('remote') -FailureMessage 'Could not verify short runtime remotes.' -Quiet)
if (@($remainingRemotes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
    throw 'Short runtime still has a Git remote after local staging; protected deployment is blocked.'
}

$required = @(
    'Bootstrap-SysAdminSuiteAutoLogon.cmd',
    'Bootstrap-SysAdminSuiteAutoLogon.ps1',
    'scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1',
    'scripts\Invoke-SasAutoLogonOnsite.ps1',
    'scripts\Invoke-SasAutoLogonFieldDeployment.ps1',
    'scripts\Set-SasHostEligibilityLocalTarget.ps1',
    'scripts\Enable-SasNorthwellVpnNetworkGuard.ps1'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $RuntimeRoot $relative) -PathType Leaf)) {
        throw "Prepared short runtime is missing required AutoLogon surface: $relative"
    }
}

$manifest = [pscustomobject][ordered]@{
    schema_version = 'sas-autologon-short-runtime/v1'
    runtime_root = $RuntimeRoot
    source_root = $SourceRoot
    prepared_commit = $runtimeHead
    prepared_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    preparation_network_classification = [string]$currentNetwork.classification
    preparation_network_label = [string]$currentNetwork.label
    runtime_git_transport = 'LOCAL_FILESYSTEM_ONLY'
    runtime_remotes_removed = $true
    protected_bootstrap_git_network_allowed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-Host ''
Write-Host 'SAS_AUTOLOGON_SHORT_RUNTIME_READY' -ForegroundColor Green
Write-Host "Runtime:  $RuntimeRoot"
Write-Host "HEAD:     $runtimeHead"
Write-Host "Manifest: $statePath"
Write-Host 'Protected-side Git network I/O: DISABLED' -ForegroundColor Green
