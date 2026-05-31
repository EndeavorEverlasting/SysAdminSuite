<#
.SYNOPSIS
    Offline smoke checks for a built portable zip and its manifest.

.DESCRIPTION
    Verifies the zip exists, SHA256 matches the manifest JSON, and optionally
    that the GUI launcher script is present inside the archive (no execution).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "Zip not found: $ZipPath"
}
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$expected = $manifest.checksumSha256
if ([string]::IsNullOrWhiteSpace($expected)) {
    throw "Manifest missing checksumSha256."
}

$actual = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash
if ($actual -ne $expected) {
    throw "SHA256 mismatch. Expected=$expected Actual=$actual"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath))
try {
    $names = $zip.Entries | ForEach-Object { $_.FullName }
    $hasGui = $names | Where-Object { $_ -match 'app[/\\]GUI[/\\]Start-SysAdminSuiteGui\.ps1' }
    if (-not $hasGui) {
        throw "Archive missing app/GUI/Start-SysAdminSuiteGui.ps1"
    }
    $hasRuntime = $names | Where-Object { $_ -match 'Launch-SysAdminSuite-Runtime\.bat' }
    if (-not $hasRuntime) {
        throw "Archive missing Launch-SysAdminSuite-Runtime.bat at repo root of package."
    }
    $hasDashboardIndex = $names | Where-Object { $_ -match 'app[/\\]dashboard[/\\]index\.html' }
    if (-not $hasDashboardIndex) {
        throw "Archive missing app/dashboard/index.html (required for PS-independent dashboard host)."
    }
    $hasHostLauncher = $names | Where-Object { $_ -match 'Launch-SysAdminSuiteDashboard\.Host\.bat' }
    if (-not $hasHostLauncher) {
        throw "Archive missing Launch-SysAdminSuiteDashboard.Host.bat at repo root of package."
    }
    $hasHostExe = $names | Where-Object { $_ -match 'app[/\\]bin[/\\]SysAdminSuite\.DashboardHost\.exe' }
    if (-not $hasHostExe) {
        Write-Warning "Archive missing app/bin/SysAdminSuite.DashboardHost.exe; PS-independent dashboard path will be unavailable until 'dotnet publish' output is staged before packaging."
    }
} finally {
    $zip.Dispose()
}

Write-Host "Smoke OK: checksum matches manifest and expected layout keys exist." -ForegroundColor Green
