<#
.SYNOPSIS
    Build a portable SysAdminSuite runtime artifact.

.DESCRIPTION
    Produces a zip package in dist/ using the contract documented in
    docs/DEPLOYMENT_ARTIFACTS.md. Intended for trusted build machines.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$distDir = Join-Path $repoRoot 'dist'
$stagingRoot = Join-Path $distDir "SysAdminSuite-Portable-v$Version"
$artifactName = "SysAdminSuite-Portable-v$Version.zip"
$artifactPath = Join-Path $distDir $artifactName

if (-not (Test-Path -LiteralPath $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}

New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'app') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'data') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'logs') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'manifest') -Force | Out-Null

$appTargets = @(
    'ActiveDirectory',
    'Config',
    'DeploymentTracker',
    'EnvSetup',
    'GetInfo',
    'GUI',
    'lib',
    'mapping',
    'OCR',
    'QRTasks',
    'tools',
    'Utilities',
    'Launch-SysAdminSuite.bat',
    'Launch-SysAdminSuite-Runtime.bat'
)

foreach ($target in $appTargets) {
    $source = Join-Path $repoRoot $target
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Warning "Skipping missing path: $source"
        continue
    }

    $destination = Join-Path (Join-Path $stagingRoot 'app') $target
    Copy-Item -Path $source -Destination $destination -Recurse -Force
}

$manifestSource = Join-Path $repoRoot 'Config\update-manifest.sample.json'
if (Test-Path -LiteralPath $manifestSource) {
    Copy-Item -Path $manifestSource -Destination (Join-Path $stagingRoot 'manifest\update-manifest.sample.json') -Force
}

if (Test-Path -LiteralPath $artifactPath) {
    Remove-Item -LiteralPath $artifactPath -Force
}

Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $artifactPath -Force
$hash = (Get-FileHash -Path $artifactPath -Algorithm SHA256).Hash

Write-Host "Portable artifact created: $artifactPath" -ForegroundColor Green
Write-Host "SHA256: $hash" -ForegroundColor Cyan
