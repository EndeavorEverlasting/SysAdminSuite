#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Start,
    [string]$End,
    [string]$Observation,
    [string]$DockType,
    [string]$DockFirmwareVersion,
    [string]$BaselinePath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$captureArgs = @{} + $PSBoundParameters
if (-not $Start -and -not $End) {
    $cutoff = [DateTimeOffset]::UtcNow
    $captureArgs.Start = $cutoff.AddMinutes(-10).ToString('o')
    $captureArgs.End = $cutoff.ToString('o')
}

function Invoke-DockGit {
    param([string[]]$GitArguments)
    $lines = & git -C $root @GitArguments
    if ($LASTEXITCODE -ne 0) { throw "Git $($GitArguments[0]) failed with exit code $LASTEXITCODE." }
    return $lines
}

try {
    $resolver = Join-Path $PSScriptRoot 'Resolve-SasCanonicalDevelopmentPath.ps1'
    $pathProof = & $resolver -CandidatePath $root -RequireCheckout -AsJson | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $pathProof.candidate_classification -ne 'CANONICAL_DEVELOPMENT') {
        throw 'Open Capture-DockIncident.cmd from the canonical SysAdminSuite development checkout.'
    }
    Import-Module (Join-Path $PSScriptRoot 'SasNetworkIntent.psm1') -Force
    $startingNetwork = Get-SasNetworkIntentState -RepoRoot $root
    Write-Host "Starting network: $($startingNetwork.classification) [$($startingNetwork.label)]"

    if (@(Invoke-DockGit @('status', '--porcelain')).Count) { throw 'The canonical checkout has local changes. Preserve them before refreshing.' }
    $branch = Invoke-DockGit @('branch', '--show-current')
    $transition = Enter-SasNetworkIntent -Intent InternetSync -RepoRoot $root
    try {
        Invoke-DockGit @('fetch', '--prune', '--tags', 'origin') | Out-Host
        $remoteHead = @(Invoke-DockGit @('ls-remote', '--symref', 'origin', 'HEAD'))
        if ($remoteHead.Count -ne 2 -or $remoteHead[0] -notmatch '^ref: refs/heads/(?<branch>[^\s]+)\s+HEAD$') {
            throw 'Could not resolve the canonical origin default branch.'
        }
        $default = $Matches.branch
        if ($branch -cne $default) { throw "Open this launcher from the canonical default branch ($default)." }
        if ($remoteHead[1] -notmatch '^(?<sha>[0-9a-f]{40})\s+HEAD$') {
            throw 'Could not resolve the canonical origin default-branch commit.'
        }
        $expected = $Matches.sha
        $fetched = Invoke-DockGit @('rev-parse', "refs/remotes/origin/$default")
        if ($fetched -ne $expected) { throw 'Origin moved during refresh. Rerun the launcher.' }
        $head = Invoke-DockGit @('rev-parse', 'HEAD')
        if ($head -ne $expected) {
            & git -C $root merge-base --is-ancestor $head $expected
            if ($LASTEXITCODE -ne 0 -or @(Invoke-DockGit @('status', '--porcelain')).Count) {
                throw 'The checkout is ahead, diverged, dirty, or incomparable. Preserve it before capture.'
            }
            Invoke-DockGit @('pull', '--ff-only', 'origin', $default) | Out-Host
        }
        if ((Invoke-DockGit @('rev-parse', 'HEAD')) -ne $expected -or @(Invoke-DockGit @('status', '--porcelain')).Count) {
            throw 'Canonical checkout currentness could not be proved.'
        }
        Invoke-DockGit @('ls-files', '--error-unmatch', 'Capture-DockIncident.cmd',
            'scripts/Open-SasDockIncident.ps1', 'scripts/Get-SasDockIncident.ps1', 'scripts/SasDockIncident.psm1') | Out-Null
        Write-Host "Verified SysAdminSuite $default at $expected."
    } finally {
        Restore-SasNetworkIntent -Transition $transition -RepoRoot $root
    }

    [void](Enter-SasNetworkIntent -Intent LocalOnly -RepoRoot $root)
    & (Join-Path $PSScriptRoot 'Get-SasDockIncident.ps1') @captureArgs
    exit $LASTEXITCODE
} catch {
    Write-Error "DOCK_CAPTURE_ADMISSION_FAILED: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
