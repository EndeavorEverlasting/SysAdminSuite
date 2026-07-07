#Requires -Version 5.1
<#
.SYNOPSIS
Moves the current PowerShell session to the SysAdminSuite app root.

.DESCRIPTION
This helper gives operators and agents a stable way to enter the repository before running
repo-relative commands. If -RepoRoot is supplied, that path is validated and used. Otherwise,
the helper resolves the repository root from this script's location.

.EXAMPLE
.\scripts\Enter-SysAdminSuite.ps1

.EXAMPLE
.\scripts\Enter-SysAdminSuite.ps1 -RepoRoot "C:\path\to\SysAdminSuite"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-SasRepoRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }

    $requiredChildren = @('docs', 'scripts', 'survey', 'harness', 'Tests')
    foreach ($child in $requiredChildren) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $child))) {
            return $false
        }
    }

    return $true
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
if (-not (Test-SasRepoRoot -Path $resolvedRoot)) {
    throw "Path does not look like the SysAdminSuite app root: $resolvedRoot"
}

Set-Location -LiteralPath $resolvedRoot

if ($PassThru.IsPresent) {
    [pscustomobject]@{
        RepoRoot = $resolvedRoot
        CurrentLocation = (Get-Location).ProviderPath
    }
}
else {
    Write-Host "SysAdminSuite app root: $resolvedRoot"
}
