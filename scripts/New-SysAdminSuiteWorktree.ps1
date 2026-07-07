#Requires -Version 5.1
<#
.SYNOPSIS
Creates a SysAdminSuite sibling worktree using the repo's canonical local layout.

.DESCRIPTION
SysAdminSuite uses a primary clone plus sibling worktrees, mirroring the Blacksmith Guild workflow.
This helper creates a sibling directory beside the current repo root and checks out the requested
branch there. It refuses to continue when the destination already exists.

.EXAMPLE
.\scripts\New-SysAdminSuiteWorktree.ps1 `
  -Name "SysAdminSuite-pr149-windows-log-classifier" `
  -Branch "sprint/windows-log-classification-system" `
  -StartPoint "main"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^SysAdminSuite-[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Branch,

    [Parameter(Mandatory = $false)]
    [string]$StartPoint = 'main',

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Resolve-SasRepoRoot {
    param([string]$RequestedRoot)

    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        return (Resolve-Path -LiteralPath $RequestedRoot).ProviderPath
    }

    return (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).ProviderPath
}

function Test-SasRepoRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    foreach ($child in @('.git', 'docs', 'scripts', 'survey', 'harness', 'Tests')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $child))) {
            return $false
        }
    }
    return $true
}

$resolvedRoot = Resolve-SasRepoRoot -RequestedRoot $RepoRoot
if (-not (Test-SasRepoRoot -Path $resolvedRoot)) {
    throw "Path does not look like the SysAdminSuite app root: $resolvedRoot"
}

$parent = Split-Path -Parent $resolvedRoot
$worktreePath = Join-Path $parent $Name

if (Test-Path -LiteralPath $worktreePath) {
    throw "Worktree path already exists: $worktreePath"
}

Set-Location -LiteralPath $resolvedRoot

if ($PSCmdlet.ShouldProcess($worktreePath, "Create SysAdminSuite sibling worktree for $Branch from $StartPoint")) {
    & git worktree add -b $Branch $worktreePath $StartPoint
    if ($LASTEXITCODE -ne 0) {
        throw "git worktree add failed with exit code $LASTEXITCODE"
    }

    [pscustomobject]@{
        RepoRoot = $resolvedRoot
        WorktreePath = $worktreePath
        Branch = $Branch
        StartPoint = $StartPoint
    }
}
