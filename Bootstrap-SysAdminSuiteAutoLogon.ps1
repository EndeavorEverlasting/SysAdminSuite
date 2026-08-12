#Requires -Version 5.1
<#
.SYNOPSIS
Acquires a durable SysAdminSuite checkout and launches the crash-safe AutoLogon field lane.

.DESCRIPTION
Resolves the Windows Desktop known folder, keeps the durable checkout under
Desktop\dev\SysAdminSuite, fetches official origin/main without rewriting an
existing checkout, creates a detached field worktree, activates the fail-closed
VPN network guard, and launches the canonical crash-safe AutoLogon runner.

The script never embeds a live target, credential, or secret. The target is
operator supplied. Existing repository edits are preserved because deployment
runs from a detached worktree at the fetched origin/main commit.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [string]$RepoUrl = 'https://github.com/EndeavorEverlasting/SysAdminSuite.git',

    [string]$InstallRoot,

    [string]$ExpectedCommit,

    [switch]$ConfirmVpnPosture
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Invoke-SasBootstrapGit {
    [CmdletBinding()]
    param(
        [string]$Root,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$FailureMessage
    )

    if ($Root) {
        & git.exe -C $Root @Arguments
    } else {
        & git.exe @Arguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (git exit $LASTEXITCODE)"
    }
}

function Resolve-SasDurableInstallRoot {
    [CmdletBinding()]
    param([string]$RequestedRoot)

    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $resolved = [System.IO.Path]::GetFullPath($RequestedRoot)
    } else {
        $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
        if ([string]::IsNullOrWhiteSpace($desktop)) {
            throw 'Windows did not resolve a Desktop known-folder path.'
        }
        $resolved = Join-Path (Join-Path $desktop 'dev') 'SysAdminSuite'
        $resolved = [System.IO.Path]::GetFullPath($resolved)
    }

    if ((Split-Path -Leaf $resolved) -ne 'SysAdminSuite') {
        throw "InstallRoot must end in SysAdminSuite: $resolved"
    }

    return $resolved
}

function Test-SasExpectedOrigin {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Url)

    $normalized = $Url.Trim().TrimEnd('/').ToLowerInvariant()
    $allowed = @(
        'https://github.com/endeavoreverlasting/sysadminsuite.git',
        'https://github.com/endeavoreverlasting/sysadminsuite',
        'git@github.com:endeavoreverlasting/sysadminsuite.git'
    )

    return $allowed -contains $normalized
}

if (-not $ConfirmVpnPosture) {
    throw 'AutoLogon field bootstrap requires -ConfirmVpnPosture.'
}

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    throw 'git.exe is not available on PATH. Install Git for Windows before field deployment.'
}

$install = Resolve-SasDurableInstallRoot -RequestedRoot $InstallRoot
$parent = Split-Path -Parent $install

Write-Host "Durable SysAdminSuite checkout: $install" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $install)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Write-Host 'No checkout exists. Cloning official SysAdminSuite...' -ForegroundColor Cyan
    Invoke-SasBootstrapGit -Arguments @('clone', '--origin', 'origin', $RepoUrl, $install) -FailureMessage 'SysAdminSuite clone failed.'
} elseif (-not (Test-Path -LiteralPath (Join-Path $install '.git'))) {
    throw "Refusing to overwrite existing non-Git folder: $install"
} else {
    Write-Host 'Existing SysAdminSuite checkout found; preserving its branch and local work.' -ForegroundColor Cyan
}

$originUrl = (& git.exe -C $install remote get-url origin 2>$null | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$originUrl)) {
    throw "Unable to resolve origin for $install"
}
$originUrl = ([string]$originUrl).Trim()
if (-not (Test-SasExpectedOrigin -Url $originUrl)) {
    throw "Refusing unexpected SysAdminSuite origin: $originUrl"
}

Invoke-SasBootstrapGit -Root $install -Arguments @('fetch', '--no-tags', '--prune', 'origin', 'refs/heads/main:refs/remotes/origin/main') -FailureMessage 'Fetching origin/main failed.'

$head = (& git.exe -C $install rev-parse 'refs/remotes/origin/main' 2>$null | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$head)) {
    throw 'Unable to resolve fetched origin/main.'
}
$head = ([string]$head).Trim()

if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and $head -ne $ExpectedCommit.Trim()) {
    throw "origin/main changed. Expected $($ExpectedCommit.Trim()), resolved $head."
}

$fieldRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-proof-worktrees'
New-Item -ItemType Directory -Path $fieldRoot -Force | Out-Null
$field = Join-Path $fieldRoot ("autologon-{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $head.Substring(0, 12))

Invoke-SasBootstrapGit -Root $install -Arguments @('worktree', 'add', '--detach', $field, $head) -FailureMessage 'Creating isolated AutoLogon field worktree failed.'

Write-Host "Field worktree: $field" -ForegroundColor Cyan
Write-Host "Field commit:   $head" -ForegroundColor Cyan

$vpnBootstrap = Join-Path $field 'scripts\Enable-SasNorthwellVpnNetworkGuard.ps1'
$crashSafeScript = Join-Path $field 'scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1'
$launcher = Join-Path $field 'Run-AutoLogonCrashSafe.cmd'

foreach ($required in @($vpnBootstrap, $crashSafeScript, $launcher)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required field deployment surface is missing: $required"
    }
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($vpnBootstrap, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    $parseErrors | Format-List * | Out-Host
    throw 'VPN network-guard bootstrap failed the PowerShell parser gate.'
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($crashSafeScript, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    $parseErrors | Format-List * | Out-Host
    throw 'Crash-safe AutoLogon runner failed the PowerShell parser gate.'
}

& $vpnBootstrap -ConfirmVpnPosture
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
if ([string]::IsNullOrWhiteSpace($env:SAS_NETWORK_GUARD_CONFIG)) {
    throw 'VPN network guard completed without activating SAS_NETWORK_GUARD_CONFIG.'
}

Write-Host ''
Write-Host 'VPN GATE PASSED - STARTING CRASH-SAFE AUTOLOGON DEPLOYMENT' -ForegroundColor Green
& $launcher $ComputerName
$deploymentExit = $LASTEXITCODE

$latestPointer = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\last-autologon-field-run.json'
Write-Host ''
Write-Host "Crash-safe latest pointer: $latestPointer" -ForegroundColor Cyan
Write-Host "Field worktree retained:    $field" -ForegroundColor Cyan

exit $deploymentExit
