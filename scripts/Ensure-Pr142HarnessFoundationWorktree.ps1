#Requires -Version 5.1
<#
.SYNOPSIS
Creates or enters the PR #142 harness-foundation sibling worktree.

.DESCRIPTION
This bootstrap is intentionally safe to run from an arbitrary PowerShell directory. It creates the
expected parent directory when missing, creates a primary clone when missing, then creates the PR #142
sibling worktree when missing. If the worktree already exists, it enters it and updates the branch.

It does not delete branches, delete worktrees, clean files, or assume the caller is already inside a
repository.

.EXAMPLE
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Ensure-Pr142HarnessFoundationWorktree.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DevRoot = 'C:\Users\Cheex\Desktop\dev\SysAdminSuite',

    [Parameter(Mandatory = $false)]
    [string]$PrimaryName = 'SysAdminSuite',

    [Parameter(Mandatory = $false)]
    [string]$WorktreeName = 'SysAdminSuite-pr142-harness-foundation',

    [Parameter(Mandatory = $false)]
    [string]$RepositoryUrl = 'https://github.com/EndeavorEverlasting/SysAdminSuite.git',

    [Parameter(Mandatory = $false)]
    [string]$Branch = 'docs/ai-layer-harness-tooling-plan'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Invoke-SasGit {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $false)][string]$WorkingDirectory
    )

    if ($WorkingDirectory) {
        Push-Location -LiteralPath $WorkingDirectory
    }
    try {
        & git @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

function Test-SasGitRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Test-Path -LiteralPath (Join-Path $Path '.git')) -and
        (Test-Path -LiteralPath (Join-Path $Path 'scripts')) -and
        (Test-Path -LiteralPath (Join-Path $Path 'Tests'))
}

New-Item -ItemType Directory -Force -Path $DevRoot | Out-Null

$primaryRoot = Join-Path $DevRoot $PrimaryName
$worktreeRoot = Join-Path $DevRoot $WorktreeName

if (-not (Test-Path -LiteralPath $primaryRoot)) {
    Write-Host "[SAS] Primary clone missing. Cloning $RepositoryUrl to $primaryRoot"
    Invoke-SasGit -Arguments @('clone', $RepositoryUrl, $primaryRoot)
}

if (-not (Test-SasGitRoot -Path $primaryRoot)) {
    throw "Primary path is not a usable SysAdminSuite git root: $primaryRoot"
}

Invoke-SasGit -WorkingDirectory $primaryRoot -Arguments @('fetch', 'origin')

if (-not (Test-Path -LiteralPath $worktreeRoot)) {
    Write-Host "[SAS] PR #142 worktree missing. Creating $worktreeRoot"
    Invoke-SasGit -WorkingDirectory $primaryRoot -Arguments @('worktree', 'add', '-B', $Branch, $worktreeRoot, "origin/$Branch")
}
else {
    Write-Host "[SAS] PR #142 worktree already exists: $worktreeRoot"
}

if (-not (Test-SasGitRoot -Path $worktreeRoot)) {
    throw "Worktree path is not a usable SysAdminSuite git root: $worktreeRoot"
}

Invoke-SasGit -WorkingDirectory $worktreeRoot -Arguments @('fetch', 'origin')
Invoke-SasGit -WorkingDirectory $worktreeRoot -Arguments @('checkout', $Branch)
Invoke-SasGit -WorkingDirectory $worktreeRoot -Arguments @('pull', '--ff-only')

Set-Location -LiteralPath $worktreeRoot

[pscustomobject]@{
    PrimaryRoot = $primaryRoot
    WorktreeRoot = $worktreeRoot
    Branch = $Branch
    CurrentLocation = (Get-Location).Path
}
