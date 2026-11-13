# P08 candidate-only local Windows live-cert guard. No Git mutation or target-network access.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ApprovedCommit)
$ErrorActionPreference = 'Stop'
try {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::UserInteractive) {
        throw 'INTERACTIVE_WINDOWS_REQUIRED'
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA_REQUIRED' }
    $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path.TrimEnd('\')
    $worktreeRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'SysAdminSuite\worktrees')).TrimEnd('\') + '\'
    if (-not $root.StartsWith($worktreeRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ISOLATED_CANONICAL_WORKTREE_REQUIRED'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $root '.git') -PathType Leaf)) {
        throw 'LINKED_GIT_WORKTREE_REQUIRED'
    }
    $git = (Get-Command git.exe -ErrorAction Stop).Source
    $toplevel = (& $git -C $root rev-parse --show-toplevel)
    if ($LASTEXITCODE -ne 0 -or
        -not [string]::Equals([IO.Path]::GetFullPath($toplevel).TrimEnd('\').Replace('\','/'), $root.Replace('\','/'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'WORKTREE_IDENTITY_MISMATCH'
    }
    $origin = (& $git -C $root remote get-url origin)
    if ($LASTEXITCODE -ne 0 -or
        $origin -notmatch '(?i)github\.com[:/]EndeavorEverlasting/SysAdminSuite(\.git)?/?$') {
        throw 'UNTRUSTED_ORIGIN_REMOTE'
    }
    $currentBranch = (& $git -C $root branch --show-current)
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'feat/chrome-audio-session-recovery-20261113') {
        throw 'EXPECTED_CANDIDATE_BRANCH_REQUIRED'
    }
    $dirty = @(& $git -C $root status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count) { throw 'DIRTY_CANDIDATE_PRESERVED' }
    $head = (& $git -C $root rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or $head -ne $ApprovedCommit.ToLowerInvariant()) {
        throw "CANDIDATE_COMMIT_MISMATCH: expected $ApprovedCommit, observed $head"
    }
    Import-Module (Join-Path $PSScriptRoot 'SasNetworkIntent.psm1') -Force
    $network = Get-SasNetworkIntentState -RepoRoot $root
    if ($network.protected -or [string]$network.classification -ne 'GUEST_INTERNET') {
        throw 'PROTECTED_OR_UNKNOWN_NETWORK: candidate may not be evaluated in a protected context'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'scripts\Invoke-SasChromeAudioRecovery.ps1'))) {
        throw 'CANDIDATE_ENTRYPOINT_MISSING'
    }
    Write-Output ('IMMUTABLE_CANDIDATE_APPROVED_FOR_LOCAL_AUDIO_TEST ' + $head)
    exit 0
}
catch {
    Write-Error ('CANDIDATE_AUDIO_CERT_BLOCKED: ' + $_.Exception.Message)
    exit 2
}
