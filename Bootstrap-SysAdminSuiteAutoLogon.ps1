#Requires -Version 5.1
<#
.SYNOPSIS
Acquire or refresh the short SysAdminSuite AutoLogon runtime and launch the crash-safe field lane.

.DESCRIPTION
Uses a stable short runtime at C:\SASAL (or -RuntimeRoot), resolves git.exe explicitly, fetches the
official origin/main without touching an operator's long or dirty working copy, pins the exact fetched
commit, preserves any legacy checkout only as an evidence fallback, and launches the crash-safe
AutoLogon child runner.

Protected-network admission remains owned by the canonical field transaction through
Confirm-SasNorthwellNetwork.ps1. When -ConfirmVpnPosture is supplied, this bootstrap first establishes a
process-local exact /32 allowlist from the currently active DomainAuthenticated non-Wi-Fi VPN/LAN
interface by invoking Enable-SasNorthwellVpnNetworkGuard.ps1. That helper performs no target contact or
mutation; the canonical field guard independently verifies the resulting current posture again before
any target operation.

When -ConfirmLocalTargetAuthorization is supplied, the bootstrap runs the canonical network gate before
DNS resolution, resolves the requested target to the canonical FQDN, and writes only that exact resolved
FQDN into the gitignored operator-local host eligibility policy using the repository authorizer. The
normal field transaction still repeats network, canonical resolution, and eligibility validation before
any target mutation.

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

    # Explicitly authorize only the canonical resolved FQDN in the ignored local host policy.
    [switch]$ConfirmLocalTargetAuthorization,

    # Explicitly establish exact current DomainAuthenticated VPN/LAN authority before the canonical gate.
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

    # StrictMode treats an unread automatic variable as an error. Prime LASTEXITCODE
    # before every native Git invocation so bootstrap diagnostics remain deterministic
    # even in a fresh PowerShell session where no native process has run yet.
    $LASTEXITCODE = 0
    $lines = if ([string]::IsNullOrWhiteSpace($Root)) {
        @(& $script:SasGitExe @Arguments 2>&1)
    } else {
        @(& $script:SasGitExe -C $Root @Arguments 2>&1)
    }
    $exitCode = [int]$LASTEXITCODE
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
    throw ('Refusing unexpected SysAdminSuite origin at {0}: {1}' -f $RuntimeRoot,$originUrl)
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
    Write-Host "Legacy evidence fallback: $legacyRoot" -ForegroundColor Cyan
} else {
    Remove-Item Env:SAS_REPO_ROOT -ErrorAction SilentlyContinue
    Write-Host 'Legacy evidence fallback: none resolved.' -ForegroundColor Yellow
}

$crashSafeScript = Join-Path $RuntimeRoot 'scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1'
$onsiteScript = Join-Path $RuntimeRoot 'scripts\Invoke-SasAutoLogonOnsite.ps1'
$networkGate = Join-Path $RuntimeRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'
$networkBootstrap = Join-Path $RuntimeRoot 'scripts\Enable-SasNorthwellVpnNetworkGuard.ps1'
$targetModule = Join-Path $RuntimeRoot 'scripts\SasTargetNameResolution.psm1'
$hostAuthorizer = Join-Path $RuntimeRoot 'scripts\Set-SasHostEligibilityLocalTarget.ps1'
foreach ($required in @($crashSafeScript,$onsiteScript,$networkGate,$networkBootstrap,$targetModule,$hostAuthorizer)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required field deployment surface is missing: $required" }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($required,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        $parseErrors | Format-List * | Out-Host
        throw "PowerShell parser gate failed: $required"
    }
}

if ($ConfirmVpnPosture) {
    Write-Host ''
    Write-Host 'ESTABLISHING EXACT CURRENT DOMAIN-AUTHENTICATED VPN/LAN AUTHORITY' -ForegroundColor Cyan
    $authority = @(& $networkBootstrap -ConfirmVpnPosture) | Select-Object -Last 1
    if ($null -eq $authority) {
        throw 'Domain transport authority bootstrap returned no structured result.'
    }
    if ([string]$authority.classification -ne 'SAS_VPN_NETWORK_GUARD_READY') {
        throw "Domain transport authority bootstrap did not complete: $($authority.classification)"
    }
    if ([bool]$authority.target_contact_performed -or [bool]$authority.target_mutation_performed) {
        throw 'Domain transport authority bootstrap violated the no-target-contact safety contract.'
    }
    $authorityConfig = [string]$authority.config_path
    if ([string]::IsNullOrWhiteSpace($authorityConfig) -or -not (Test-Path -LiteralPath $authorityConfig -PathType Leaf)) {
        throw "Domain transport authority config was not created: $authorityConfig"
    }
    $env:SAS_NETWORK_GUARD_CONFIG = $authorityConfig
    Write-Host "Exact current domain transport authority activated: $authorityConfig" -ForegroundColor Green
    Write-Host 'The canonical field guard will independently verify this posture before target contact.' -ForegroundColor Green
} else {
    Remove-Item Env:SAS_NETWORK_GUARD_CONFIG -ErrorAction SilentlyContinue
}

if ($ConfirmLocalTargetAuthorization) {
    if (-not $ConfirmVpnPosture) {
        throw 'Exact canonical target authorization requires -ConfirmVpnPosture so protected-network admission precedes DNS resolution.'
    }

    Write-Host ''
    Write-Host 'PROVING NETWORK BEFORE CANONICAL TARGET AUTHORIZATION' -ForegroundColor Cyan
    $LASTEXITCODE = 0
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $networkGate `
        -Purpose "AutoLogon bootstrap authorization for $ComputerName"
    if ($LASTEXITCODE -ne 0) {
        throw "Canonical target authorization stopped by the protected network gate with exit code $LASTEXITCODE."
    }

    Import-Module $targetModule -Force
    $authorizationResolution = Resolve-SasCanonicalTargetFqdn -TargetName $ComputerName
    if (@($authorizationResolution.addresses).Count -lt 1) {
        throw 'Canonical target authorization resolution returned no address.'
    }
    $resolvedAuthorizationTarget = [string]$authorizationResolution.fqdn
    if ([string]::IsNullOrWhiteSpace($resolvedAuthorizationTarget)) {
        throw 'Canonical target authorization resolution returned an empty FQDN.'
    }

    Write-Host ''
    Write-Host 'AUTHORIZING EXACT CANONICAL AUTOLOGON TARGET' -ForegroundColor Cyan
    $authorization = & $hostAuthorizer -Target $resolvedAuthorizationTarget -ExecContext remote `
        -RepoRoot $RuntimeRoot -ConfirmLocalAuthorization -PassThru
    if ($null -eq $authorization -or -not [bool]$authorization.eligible -or
        [string]$authorization.decision -ne 'allowed') {
        throw "Exact canonical target authorization failed for $resolvedAuthorizationTarget."
    }
    Write-Host "Canonical target authorized: $resolvedAuthorizationTarget" -ForegroundColor Green
    Write-Host "Operator-local policy: $($authorization.policy_path)" -ForegroundColor Green
    Write-Host 'The canonical field transaction will independently re-resolve and revalidate this exact target.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'SHORT RUNTIME PINNED - STARTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION' -ForegroundColor Green
Write-Host "Runtime HEAD: $runtimeHead" -ForegroundColor Green
Write-Host 'Network authority: canonical Confirm-SasNorthwellNetwork.ps1 inside the field transaction' -ForegroundColor Green

# Prime LASTEXITCODE for the same StrictMode reason as native Git above.
$LASTEXITCODE = 0
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $crashSafeScript `
    -ComputerName $ComputerName -RepositoryRoot $RuntimeRoot -ConfirmDeployment
$deploymentExit = [int]$LASTEXITCODE

$latestPointer = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\last-autologon-field-run.json'
Write-Host ''
Write-Host "Crash-safe latest pointer: $latestPointer" -ForegroundColor Cyan
Write-Host "Short runtime retained:     $RuntimeRoot" -ForegroundColor Cyan
Write-Host "Runtime commit:             $runtimeHead" -ForegroundColor Cyan

exit $deploymentExit
