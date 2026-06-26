#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-SasRepoRoot {
    [CmdletBinding()]
    param([string]$StartPath)

    $cursor = if ($StartPath) { [System.IO.Path]::GetFullPath($StartPath) } else { (Get-Location).Path }
    if (Test-Path -LiteralPath $cursor -PathType Leaf) {
        $cursor = Split-Path -Parent $cursor
    }

    while ($cursor) {
        if ((Test-Path -LiteralPath (Join-Path $cursor 'targets/README.md')) -and
            (Test-Path -LiteralPath (Join-Path $cursor 'survey'))) {
            return $cursor
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }

    throw 'Unable to resolve SysAdminSuite repo root.'
}

function Get-SasTargetIntakeRoots {
    [CmdletBinding()]
    param([string]$RepoRoot)

    if (-not $RepoRoot) { $RepoRoot = Get-SasRepoRoot }
    [pscustomobject]@{
        SourceRoots = @(
            (Join-Path $RepoRoot 'targets/local'),
            (Join-Path $RepoRoot 'logs/targets')
        )
        StagingRoot = Join-Path $RepoRoot 'survey/input'
        InputRoots  = @(
            (Join-Path $RepoRoot 'targets/local'),
            (Join-Path $RepoRoot 'logs/targets'),
            (Join-Path $RepoRoot 'survey/input')
        )
        OutputRoots = @(
            (Join-Path $RepoRoot 'survey/output'),
            (Join-Path $RepoRoot 'logs/nmap'),
            (Join-Path $RepoRoot 'survey/artifacts')
        )
        FixtureRoots = @(
            (Join-Path $RepoRoot 'survey/fixtures'),
            (Join-Path $RepoRoot 'targets/sanitized')
        )
    }
}

function ConvertTo-SasFullPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Test-SasPathUnderRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = ConvertTo-SasFullPath -Path $Path
    $fullRoot = ConvertTo-SasFullPath -Path $Root
    if (-not $fullRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $fullRoot = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    }

    return $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-SasPathUnderAnyRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Roots
    )

    foreach ($root in $Roots) {
        if (Test-SasPathUnderRoot -Path $Path -Root $root) { return $true }
    }
    return $false
}

function Get-SasCandidateTargetFile {
    [CmdletBinding()]
    param(
        [string]$RepoRoot,
        [switch]$IncludeStaging
    )

    if (-not $RepoRoot) { $RepoRoot = Get-SasRepoRoot }
    $roots = Get-SasTargetIntakeRoots -RepoRoot $RepoRoot
    $scanRoots = @($roots.SourceRoots)
    if ($IncludeStaging) { $scanRoots += $roots.StagingRoot }

    foreach ($root in $scanRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.txt', '.csv') } |
            Sort-Object FullName
    }
}

function Assert-SasApprovedInputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$RepoRoot,
        [string]$Role = 'target input',
        [switch]$AllowStaging,
        [switch]$AllowFixtures,
        [switch]$AllowNonstandard
    )

    if (-not $RepoRoot) { $RepoRoot = Get-SasRepoRoot }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Role not found: $Path"
    }

    $roots = Get-SasTargetIntakeRoots -RepoRoot $RepoRoot
    $approved = @($roots.SourceRoots)
    if ($AllowStaging) { $approved += $roots.StagingRoot }
    if ($AllowFixtures) { $approved += $roots.FixtureRoots }

    if (-not (Test-SasPathUnderAnyRoot -Path (Resolve-Path -LiteralPath $Path).Path -Roots $approved)) {
        if ($AllowNonstandard) {
            Write-Warning "NONSTANDARD INPUT OVERRIDE: $Role is outside codified target intake roots: $Path"
            return
        }
        throw "$Role is outside approved target intake roots. Use targets/local/ or logs/targets/ first; survey/input/ only after normalization. Refusing: $Path"
    }
}

function Assert-SasApprovedOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$RepoRoot,
        [string]$Role = 'generated output',
        [switch]$AllowNonstandard
    )

    if (-not $RepoRoot) { $RepoRoot = Get-SasRepoRoot }
    $roots = Get-SasTargetIntakeRoots -RepoRoot $RepoRoot
    if (-not (Test-SasPathUnderAnyRoot -Path $Path -Roots $roots.OutputRoots)) {
        if ($AllowNonstandard) {
            Write-Warning "NONSTANDARD OUTPUT OVERRIDE: $Role is outside codified generated output roots: $Path"
            return
        }
        throw "$Role is outside approved generated output roots. Use survey/output/, logs/nmap/, or survey/artifacts/. Refusing: $Path"
    }
}

Export-ModuleMember -Function Get-SasRepoRoot, Get-SasTargetIntakeRoots, ConvertTo-SasFullPath, Test-SasPathUnderRoot, Test-SasPathUnderAnyRoot, Get-SasCandidateTargetFile, Assert-SasApprovedInputPath, Assert-SasApprovedOutputPath
