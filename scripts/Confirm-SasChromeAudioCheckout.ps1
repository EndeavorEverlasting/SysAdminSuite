# Fail-closed operator preflight for a cloned, canonical Windows development checkout.
# No network switching, force/reset/checkout, branch creation, or policy changes.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
try {
    $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path.TrimEnd('\')
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktop)) { throw 'DESKTOP_KNOWN_FOLDER_UNAVAILABLE' }
    $canonical = [IO.Path]::GetFullPath((Join-Path $desktop 'Dev\SysAdminSuite')).TrimEnd('\')
    if (-not [string]::Equals($root, $canonical, [StringComparison]::OrdinalIgnoreCase)) {
        throw "CANONICAL_CHECKOUT_REQUIRED: expected $canonical; observed $root"
    }
    Import-Module (Join-Path $PSScriptRoot 'SasNetworkIntent.psm1') -Force
    $starting = Get-SasNetworkIntentState -RepoRoot $root
    # Never initiate Git activity from a protected/unknown network or switch networks for audio.
    if ([bool]$starting.protected -or [string]$starting.classification -ne 'GUEST_INTERNET') {
        throw "INTERNET_SYNC_REQUIRED: current $($starting.classification) [$($starting.label)]. No network transition attempted."
    }

    $git = Get-Command git.exe -ErrorAction Stop
    $gitPath = [string]$git.Source
    $actualRoot = (& $gitPath -C $root rev-parse --show-toplevel)
    if ($LASTEXITCODE -ne 0) { throw 'GIT_WORKTREE_UNHEALTHY' }
    if (-not [string]::Equals(
        [IO.Path]::GetFullPath($actualRoot).TrimEnd('\').Replace('\','/'),
        $root.Replace('\','/'),
        [StringComparison]::OrdinalIgnoreCase
    )) { throw 'GIT_TOPLEVEL_MISMATCH' }

    $remote = (& $gitPath -C $root remote get-url origin)
    if ($LASTEXITCODE -ne 0 -or $remote -notmatch '(?i)github\.com[:/]EndeavorEverlasting/SysAdminSuite(\.git)?/?$') {
        throw 'UNTRUSTED_ORIGIN_REMOTE'
    }
    $branch = (& $gitPath -C $root branch --show-current)
    if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') {
        throw 'CANONICAL_MAIN_BRANCH_REQUIRED'
    }
    $dirty = @(& $gitPath -C $root status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) {
        throw 'DIRTY_CHECKOUT_PRESERVED'
    }
    & $gitPath -C $root fetch origin --prune --tags
    if ($LASTEXITCODE -ne 0) { throw 'REMOTE_FRESHNESS_FETCH_FAILED' }
    $remoteHead = (& $gitPath -C $root rev-parse --verify refs/remotes/origin/main)
    if ($LASTEXITCODE -ne 0) { throw 'REMOTE_MAIN_MISSING' }
    $head = (& $gitPath -C $root rev-parse HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'LOCAL_HEAD_UNAVAILABLE' }
    if ($head -ne $remoteHead) {
        & $gitPath -C $root merge-base --is-ancestor HEAD refs/remotes/origin/main
        if ($LASTEXITCODE -ne 0) { throw 'DIVERGED_CHECKOUT_PRESERVED' }
        & $gitPath -C $root pull --ff-only origin main
        if ($LASTEXITCODE -ne 0) { throw 'CLEAN_FAST_FORWARD_FAILED' }
        $head = (& $gitPath -C $root rev-parse HEAD)
        if ($LASTEXITCODE -ne 0 -or $head -ne $remoteHead) {
            throw 'POST_PULL_HEAD_MISMATCH'
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'scripts\Invoke-SasChromeAudioRecovery.ps1'))) {
        throw 'CHROME_AUDIO_ENTRYPOINT_MISSING_AT_REFRESHED_HEAD'
    }
    $ending = Get-SasNetworkIntentState -RepoRoot $root
    if ($starting.classification -ne $ending.classification -or
        $starting.label -ne $ending.label -or
        $starting.authority -ne $ending.authority) {
        throw 'STARTING_NETWORK_POSTURE_CHANGED'
    }
    Write-Output ('CHECKOUT_CURRENT_AND_LOCAL_NETWORK_UNCHANGED ' + $head)
    exit 0
}
catch {
    Write-Error ('CHROME_AUDIO_LAUNCH_BLOCKED: ' + $_.Exception.Message)
    exit 2
}
