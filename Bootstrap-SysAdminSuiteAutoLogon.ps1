#Requires -Version 5.1
<#
.SYNOPSIS
Acquire or refresh the short SysAdminSuite AutoLogon runtime and launch the crash-safe field lane.

.DESCRIPTION
Uses a stable short runtime at C:\SASAL (or -RuntimeRoot), resolves git.exe explicitly, fetches the
official origin/main without touching an operator's long or dirty working copy, pins the exact fetched
commit, preserves any legacy checkout only as an evidence/network-policy fallback, and launches the
crash-safe AutoLogon child runner.

Protected-network admission is owned only by the canonical field transaction through
Confirm-SasNorthwellNetwork.ps1. The legacy DomainAuthenticated-only VPN bootstrap is not a prerequisite
and this script never writes a local network allowlist.

Existing unexpected or dirty runtime content is never reset, cleaned, removed, or overwritten.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [string]$RepoUrl = 'https://github.com/EndeavorEverlasting/SysAdminSuite.git',

    [string]$RuntimeRoot = 'C:\SASAL',

    [string]$LegacyEvidenceRoot,

    [string]$ExpectedCommit,

    # Backward-compatible acknowledgement only. Canonical network admission is still performed later.
    [switch]$ConfirmVpnPosture
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Resolve-SasGitExecutable {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $command = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) { [void]$candidates.Add([string]$command.Source) }

    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path $env:ProgramFiles 'Git\bin\git.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $candidates.Contains($candidate)) {
            [void]$candidates.Add($candidate)
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    throw 'Git for Windows could not be resolved. Checked PATH, Program Files\Git, and LocalAppData\Programs\Git.'
}

$script:SasGitExe = Resolve-SasGitExecutable

function Invoke-SasBootstrapGit {
    [CmdletBinding()]
    param(
        [string]$Root,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$FailureMessage,
        [switch]$Quiet
    )

    $lines = if ([string]::IsNullOrWhiteSpace($Root)) {
        @(& $script:SasGitExe @Arguments 2>&1)
    } else {
        @(& $script:SasGitExe -C $Root @Arguments 2>&1)
    }
    $exitCode = $LASTEXITCODE
    $text = (@($lines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()

    if (-not $Quiet -and -not [string]::IsNullOrWhiteSpace($text)) {
        Write-Host $text
    }
    if ($exitCode -ne 0) {
        $detail = if ([string]::IsNullOrWhiteSpace($text)) { '(git produced no diagnostic text)' } else { $text }
        throw "$FailureMessage (git exit $exitCode)`n$detail"
    }

    return @($lines | ForEach-Object { [string]$_ })
}

function Get-SasGitScalar {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$FailureMessage
    )
    $lines = @(Invoke-SasBootstrapGit -Root $Root -Arguments $Arguments -FailureMessage $FailureMessage -Quiet)
    $value = [string]($lines | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$FailureMessage (empty git output)" }
    return $value.Trim()
}

function Test-SasExpectedOrigin {
    param([Parameter(Mandatory)][string]$Url)
    $normalized = $Url.Trim().TrimEnd('/').ToLowerInvariant()
    return $normalized -in @(
        'https://github.com/endeavoreverlasting/sysadminsuite.git',
        'https://github.com/endeavoreverlasting/sysadminsuite',
        'git@github.com:endeavoreverlasting/sysadminsuite.git'
    )
}

function Resolve-SasLegacyEvidenceRoot {
    param([string]$RequestedRoot,[string]$Runtime)

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in @($RequestedRoot, [string](Get-Location))) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $candidates.Contains($candidate)) {
            [void]$candidates.Add($candidate)
        }
    }

    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
    if (-not [string]::IsNullOrWhiteSpace($desktop)) {
        $durable = Join-Path (Join-Path $desktop 'dev') 'SysAdminSuite'
        if (-not $candidates.Contains($durable)) { [void]$candidates.Add($durable) }
    }

    foreach ($candidate in $candidates) {
        try { $full = [IO.Path]::GetFullPath($candidate) } catch { continue }
        if ($full.TrimEnd('\').Equals($Runtime.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
        if ((Test-Path -LiteralPath (Join-Path $full 'survey\output') -PathType Container) -or
            (Test-Path -LiteralPath (Join-Path $full 'Config') -PathType Container) -or
            (Test-Path -LiteralPath (Join-Path $full 'scripts\Invoke-SasAutoLogonFieldDeployment.ps1') -PathType Leaf)) {
            return $full
        }
    }
    return $null
}

$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$runtimeParent = Split-Path -Parent $RuntimeRoot
Write-Host "Git executable: $script:SasGitExe" -ForegroundColor Cyan
Write-Host "Short AutoLogon runtime: $RuntimeRoot" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $RuntimeRoot)) {
    New-Item -ItemType Directory -Path $runtimeParent -Force | Out-Null
    Write-Host 'Short runtime does not exist; cloning official SysAdminSuite...' -ForegroundColor Cyan
    [void](Invoke-SasBootstrapGit -Arguments @('clone','--origin','origin',$RepoUrl,$RuntimeRoot) -FailureMessage 'Cloning the short SysAdminSuite runtime failed.')
} else {
    if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
        throw "Refusing runtime path because it is not a directory: $RuntimeRoot"
    }
    $inside = Get-SasGitScalar -Root $RuntimeRoot -Arguments @('rev-parse','--is-inside-work-tree') -FailureMessage "Existing short runtime is not a usable Git worktree: $RuntimeRoot"
    if ($inside -ne 'true') {
        throw "Existing short runtime is not a Git worktree: $RuntimeRoot"
    }
    Write-Host 'Existing short runtime found; preserving it and validating ownership.' -ForegroundColor Cyan
}

$originUrl = Get-SasGitScalar -Root $RuntimeRoot -Arguments @('remote','get-url','origin') -FailureMessage 'Unable to resolve short-runtime origin.'
if (-not (Test-SasExpectedOrigin -Url $originUrl)) {
    throw "Refusing unexpected SysAdminSuite origin at $RuntimeRoot: $originUrl"
}

$dirty = @(Invoke-SasBootstrapGit -Root $RuntimeRoot -Arguments @('status','--porcelain') -FailureMessage 'Unable to inspect short-runtime worktree state.' -Quiet)
if (@($dirty | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw "Short runtime contains uncommitted/untracked work and will not be reset or cleaned: $RuntimeRoot"
}

[void](Invoke-SasBootstrapGit -Root $RuntimeRoot -Arguments @('fetch','--no-tags','--prune','origin','refs/heads/main:refs/remotes/origin/main') -FailureMessage 'Fetching official origin/main failed. VPN/internet access may be required for refresh.')
$head = Get-SasGitScalar -Root $RuntimeRoot -Arguments @('rev-parse','refs/remotes/origin/main') -FailureMessage 'Unable to resolve fetched origin/main.'

if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and $head -ne $ExpectedCommit.Trim()) {
    throw "origin/main changed. Expected $($ExpectedCommit.Trim()), resolved $head."
}

[void](Invoke-SasBootstrapGit -Root $RuntimeRoot -Arguments @('checkout','--detach',$head) -FailureMessage "Unable to pin short runtime to fetched main $head")
$runtimeHead = Get-SasGitScalar -Root $RuntimeRoot -Arguments @('rev-parse','HEAD') -FailureMessage 'Unable to verify short-runtime HEAD after checkout.'
if ($runtimeHead -ne $head) { throw "Short-runtime HEAD mismatch after checkout. Expected $head, resolved $runtimeHead" }

$legacyRoot = Resolve-SasLegacyEvidenceRoot -RequestedRoot $LegacyEvidenceRoot -Runtime $RuntimeRoot
if ($legacyRoot) {
    $env:SAS_REPO_ROOT = $legacyRoot
    $legacyNetworkConfig = Join-Path $legacyRoot 'Config\sas-network-guard.local.json'
    if (Test-Path -LiteralPath $legacyNetworkConfig -PathType Leaf) {
        $env:SAS_NETWORK_GUARD_CONFIG = $legacyNetworkConfig
    }
    Write-Host "Legacy evidence/config fallback: $legacyRoot" -ForegroundColor Cyan
} else {
    Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:SAS_NETWORK_GUARD_CONFIG -ErrorAction SilentlyContinue
    Write-Host 'Legacy evidence/config fallback: none resolved.' -ForegroundColor Yellow
}

if ($ConfirmVpnPosture) {
    Write-Host '-ConfirmVpnPosture acknowledged. It does not grant network authority; the canonical field guard will verify current posture.' -ForegroundColor DarkCyan
}

$crashSafeScript = Join-Path $RuntimeRoot 'scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1'
$onsiteScript = Join-Path $RuntimeRoot 'scripts\Invoke-SasAutoLogonOnsite.ps1'
$networkGate = Join-Path $RuntimeRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
foreach ($required in @($crashSafeScript,$onsiteScript,$networkGate)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required field deployment surface is missing: $required" }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($required,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        $parseErrors | Format-List * | Out-Host
        throw "PowerShell parser gate failed: $required"
    }
}

Write-Host ''
Write-Host 'SHORT RUNTIME PINNED - STARTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION' -ForegroundColor Green
Write-Host "Runtime HEAD: $runtimeHead" -ForegroundColor Green
Write-Host 'Network authority: canonical Confirm-SasNorthwellNetwork.ps1 inside the field transaction' -ForegroundColor Green

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $crashSafeScript `
    -ComputerName $ComputerName -RepositoryRoot $RuntimeRoot -ConfirmDeployment
$deploymentExit = $LASTEXITCODE

$latestPointer = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\last-autologon-field-run.json'
Write-Host ''
Write-Host "Crash-safe latest pointer: $latestPointer" -ForegroundColor Cyan
Write-Host "Short runtime retained:     $RuntimeRoot" -ForegroundColor Cyan
Write-Host "Runtime commit:             $runtimeHead" -ForegroundColor Cyan

exit $deploymentExit
