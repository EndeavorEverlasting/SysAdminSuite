#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Invoke-ClockGit {
    param([string[]]$GitArguments)
    $output = & git -C $root @GitArguments
    if ($LASTEXITCODE -ne 0) { throw "Git $($GitArguments[0]) failed with exit code $LASTEXITCODE." }
    return $output
}

try {
    $resolver = Join-Path $root 'scripts/Resolve-SasCanonicalDevelopmentPath.ps1'
    $pathProof = & $resolver -CandidatePath $root -RequireCheckout -AsJson | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $pathProof.candidate_classification -ne 'CANONICAL_DEVELOPMENT') {
        throw 'Open this launcher from the canonical SysAdminSuite development checkout.'
    }
    Import-Module (Join-Path $root 'scripts/SasNetworkIntent.psm1')
    $startingNetwork = Get-SasNetworkIntentState -RepoRoot $root
    Write-Host "Starting network: $($startingNetwork.classification) [$($startingNetwork.label)]"
    if (@(Invoke-ClockGit @('status', '--porcelain')).Count) { throw 'Preserve existing changes before refreshing this checkout.' }
    $localBranch = Invoke-ClockGit @('branch', '--show-current')
    if ($localBranch -ne 'main') { throw 'Use the canonical checkout on main.' }
    $transition = Enter-SasNetworkIntent -Intent InternetSync -RepoRoot $root -AllowAutomaticWlanTransition

    try {
        Invoke-ClockGit @('fetch', '--all', '--prune', '--tags') | Out-Host
        $remoteHead = @(Invoke-ClockGit @('ls-remote', '--symref', 'origin', 'HEAD'))
        if ($remoteHead.Count -ne 2 -or $remoteHead[0] -notmatch '^ref: refs/heads/main\s+HEAD$' -or
            $remoteHead[1] -notmatch '^([0-9a-f]{40})\s+HEAD$') {
            throw 'Unable to verify origin main as the current default branch.'
        }
        $expected = $Matches[1]
        $fetched = Invoke-ClockGit @('rev-parse', 'refs/remotes/origin/main')
        if ($fetched -ne $expected) { throw 'Origin main moved during refresh. Reopen the launcher to retry.' }
        $head = Invoke-ClockGit @('rev-parse', 'HEAD')
        if ($head -ne $expected) {
            & git -C $root merge-base --is-ancestor $head $expected
            if ($LASTEXITCODE -ne 0 -or @(Invoke-ClockGit @('status', '--porcelain')).Count) {
                throw 'Checkout is ahead, diverged, dirty, or could not be compared. Preserve it for review.'
            }
            Invoke-ClockGit @('pull', '--ff-only', 'origin', 'main') | Out-Host
        }
        if ((Invoke-ClockGit @('rev-parse', 'HEAD')) -ne $expected -or
            @(Invoke-ClockGit @('status', '--porcelain')).Count) {
            throw 'Checkout currentness could not be proved.'
        }
        Write-Host "Verified SysAdminSuite main: $expected"
    } finally {
        Restore-SasNetworkIntent -Transition $transition -RepoRoot $root
    }

    $launcher = Join-Path $PSScriptRoot 'Start-KronosClockBatch.ps1'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'Current main is missing the clock launcher.' }
    & $launcher
    exit $LASTEXITCODE
} catch {
    Write-Host "BLOCKED: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
