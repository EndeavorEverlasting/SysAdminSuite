<#
.SYNOPSIS
    Build a lean field-release ZIP for the SysAdminSuite dashboard (no .NET SDK on target).

.DESCRIPTION
    Produces dist/SysAdminSuite-Dashboard-Field-v{Version}.zip with:
      - START-HERE-SysAdminSuite-Dashboard.bat (canonical launcher)
      - Launch-SysAdminSuiteDashboard.Host.bat
      - dashboard/ web assets
      - app/bin/SysAdminSuite.DashboardHost.exe (+ runtime deps)
      - START-HERE-SysAdminSuite.md (lay-user guide)

    Intended for trusted build machines with the .NET 8 SDK. Output stays in
    gitignored dist/ — upload to GitHub Releases or an approved share; do not
    commit the zip to git.

    See docs/DASHBOARD_FIELD_RELEASE.md for source-clone vs field-package guidance.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$Configuration = 'Release',
    [string]$RuntimeIdentifier = 'win-x64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$distDir = Join-Path $repoRoot 'dist'
$stagingRoot = Join-Path $distDir "SysAdminSuite-Dashboard-Field-v$Version"
$artifactName = "SysAdminSuite-Dashboard-Field-v$Version.zip"
$artifactPath = Join-Path $distDir $artifactName
$publishScript = Join-Path $repoRoot 'tools\publish-dashboard-entrypoint.ps1'

if (-not (Test-Path -LiteralPath $publishScript)) {
    throw "Publish script not found: $publishScript"
}

if (-not (Test-Path -LiteralPath $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}

Write-Host "Publishing dashboard host (framework-dependent, $RuntimeIdentifier)..."
& $publishScript -Configuration $Configuration -RuntimeIdentifier $RuntimeIdentifier

$publishOutput = Join-Path $repoRoot 'dist\SysAdminSuiteDashboard'
$hostExe = Join-Path $publishOutput 'SysAdminSuite.DashboardHost.exe'
if (-not (Test-Path -LiteralPath $hostExe)) {
    throw "Dashboard host publish failed; expected full publish output at: $publishOutput"
}

New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'app\bin') -Force | Out-Null

$rootFiles = @(
    'START-HERE-SysAdminSuite-Dashboard.bat',
    'START-HERE-SysAdminSuite-Dashboard.cmd',
    'SysAdminSuite Dashboard.cmd',
    'Launch-SysAdminSuiteDashboard.Host.bat',
    'START-HERE-SysAdminSuite.md'
)

foreach ($file in $rootFiles) {
    $source = Join-Path $repoRoot $file
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required field-release file missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $stagingRoot $file) -Force
}

$dashboardSource = Join-Path $repoRoot 'dashboard'
if (-not (Test-Path -LiteralPath $dashboardSource)) {
    throw "dashboard/ folder missing at repo root"
}
Copy-Item -Path $dashboardSource -Destination (Join-Path $stagingRoot 'dashboard') -Recurse -Force

Copy-Item -Path (Join-Path $publishOutput '*') -Destination (Join-Path $stagingRoot 'app\bin') -Recurse -Force

$fieldReadme = @"
# SysAdminSuite Dashboard — Field Release

This is a **field release package**. The dashboard host is already built under
``app/bin/``. You do **not** need the .NET SDK on this machine.

## Start

Double-click:

``START-HERE-SysAdminSuite-Dashboard.bat``

Your browser opens the local dashboard and Cybernet tutorial.

## Requirements

- Windows 10 or later
- .NET 8 **runtime** (not the SDK) — usually already present on managed PCs

## Not a source checkout

If you need to change survey scripts or develop against git, use a **source clone**
instead. See docs/DASHBOARD_FIELD_RELEASE.md in the full repository.

Version: $Version
"@
Set-Content -LiteralPath (Join-Path $stagingRoot 'FIELD-RELEASE-README.txt') -Value $fieldReadme -Encoding UTF8

if (Test-Path -LiteralPath $artifactPath) {
    Remove-Item -LiteralPath $artifactPath -Force
}

Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $artifactPath -Force
$hash = (Get-FileHash -Path $artifactPath -Algorithm SHA256).Hash

$commit = $null
try {
    Push-Location $repoRoot
    $commit = (& git rev-parse HEAD 2>$null)
} finally {
    Pop-Location
}

$manifestPath = Join-Path $distDir "SysAdminSuite-Dashboard-Field-v$Version.manifest.json"
$manifest = [ordered]@{
    version        = $Version
    package        = $artifactName
    checksumSha256 = $hash
    publishedUtc   = (Get-Date).ToUniversalTime().ToString('o')
    notes          = 'Dashboard field release; includes pre-built host under app/bin/. Requires .NET 8 runtime on target.'
    artifactPath   = $artifactName
    layout         = 'app/bin/SysAdminSuite.DashboardHost.exe at package root'
}
if ($commit) {
    $manifest['gitCommit'] = $commit.Trim()
}
($manifest | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host ""
Write-Host "Dashboard field release created: $artifactPath" -ForegroundColor Green
Write-Host "SHA256: $hash" -ForegroundColor Cyan
Write-Host "Manifest: $manifestPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Field users: extract the zip, then double-click START-HERE-SysAdminSuite-Dashboard.bat"
