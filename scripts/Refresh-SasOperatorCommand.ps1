#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepositoryRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
else {
    $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git) { $git = Get-Command git -ErrorAction SilentlyContinue }
if (-not $git) { throw 'Git for Windows is required to refresh the field-ready SysAdminSuite checkout.' }

& $git.Source -C $RepositoryRoot rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Not a Git working tree: $RepositoryRoot"
}

Write-Host 'Refreshing SysAdminSuite operator surface from origin/main...' -ForegroundColor Cyan
& $git.Source -C $RepositoryRoot fetch --prune origin main
if ($LASTEXITCODE -ne 0) { throw "git fetch origin main failed with exit code $LASTEXITCODE" }

$remoteHead = (& $git.Source -C $RepositoryRoot rev-parse origin/main).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteHead)) {
    throw 'Could not resolve origin/main after fetch.'
}

$stateRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite'
$preferred = Join-Path $stateRoot 'field-ready'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Test-SameRepository {
    param([Parameter(Mandatory = $true)][string]$Candidate)
    if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) { return $false }
    try {
        $candidateOrigin = (& $git.Source -C $Candidate remote get-url origin 2>$null | Select-Object -First 1)
        $sourceOrigin = (& $git.Source -C $RepositoryRoot remote get-url origin 2>$null | Select-Object -First 1)
        return (
            $LASTEXITCODE -eq 0 -and
            -not [string]::IsNullOrWhiteSpace([string]$candidateOrigin) -and
            ([string]$candidateOrigin).Trim().Equals(([string]$sourceOrigin).Trim(), [StringComparison]::OrdinalIgnoreCase)
        )
    }
    catch { return $false }
}

$fieldReady = $preferred
if (Test-Path -LiteralPath $fieldReady) {
    $sameRepo = Test-SameRepository -Candidate $fieldReady
    $dirty = @()
    if ($sameRepo) {
        $dirty = @(& $git.Source -C $fieldReady status --porcelain 2>$null)
    }
    if (-not $sameRepo -or $LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) {
        $fieldReady = Join-Path $stateRoot ('field-ready-' + (Get-Date).ToString('yyyyMMdd-HHmmss'))
    }
}

if (-not (Test-Path -LiteralPath $fieldReady)) {
    & $git.Source -C $RepositoryRoot worktree add --detach $fieldReady origin/main
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create isolated field-ready worktree: $fieldReady"
    }
}
else {
    & $git.Source -C $fieldReady checkout --detach origin/main
    if ($LASTEXITCODE -ne 0) {
        throw "Could not refresh isolated field-ready worktree: $fieldReady"
    }
}

$head = (& $git.Source -C $fieldReady rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $remoteHead) {
    throw "Field-ready HEAD mismatch. Expected $remoteHead; got $head"
}

$required = @(
    'Install-SasOperatorCommand.cmd',
    'scripts\Install-SasPortableLauncher.ps1',
    'scripts\SasPortableLauncher.ps1',
    'Find-SasEvidence.cmd',
    'Deploy-CybernetSoftware.cmd',
    'Probe-CybernetSoftware.cmd'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $fieldReady $relative) -PathType Leaf)) {
        throw "Refreshed origin/main is missing required operator surface: $relative"
    }
}

$installer = Join-Path $fieldReady 'scripts\Install-SasPortableLauncher.ps1'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer
if ($LASTEXITCODE -ne 0) {
    throw "Operator-command refresh installer failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'SAS_OPERATOR_REFRESH_READY' -ForegroundColor Green
Write-Host "Field-ready repo: $fieldReady"
Write-Host "HEAD: $head"
Write-Host 'Existing source worktree was not reset or cleaned.' -ForegroundColor Green
Write-Host 'Next: run `sas` to see the current bounded command surface.' -ForegroundColor Cyan
