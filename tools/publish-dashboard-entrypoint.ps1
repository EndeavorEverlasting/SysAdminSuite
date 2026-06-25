# Publish the PS-independent dashboard tray host for field use.
# Output is local-only (gitignored). Not committed to the repo.
#
# Usage (from repo root):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\publish-dashboard-entrypoint.ps1
#
# Produces:
#   dist/SysAdminSuiteDashboard/SysAdminSuite Dashboard.exe
#   dist/SysAdminSuiteDashboard/SysAdminSuite.DashboardHost.exe (same binary, technical name)

[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [string]$RuntimeIdentifier = 'win-x64',
    [string]$OutputRoot = 'dist/SysAdminSuiteDashboard'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repoRoot 'src/SysAdminSuite.DashboardHost/SysAdminSuite.DashboardHost.csproj'
$publishDir = Join-Path $repoRoot ($OutputRoot -replace '/', [IO.Path]::DirectorySeparatorChar)
$friendlyName = 'SysAdminSuite Dashboard.exe'
$technicalName = 'SysAdminSuite.DashboardHost.exe'

if (-not (Test-Path -LiteralPath $project)) {
    throw "Dashboard host project not found: $project"
}

Write-Host "Publishing dashboard host to $publishDir ..."
dotnet publish $project -c $Configuration -r $RuntimeIdentifier --self-contained false -o $publishDir
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

$technicalPath = Join-Path $publishDir $technicalName
if (-not (Test-Path -LiteralPath $technicalPath)) {
    throw "Expected publish output missing: $technicalPath"
}

$friendlyPath = Join-Path $publishDir $friendlyName
Copy-Item -LiteralPath $technicalPath -Destination $friendlyPath -Force

$toolsPublish = Join-Path $repoRoot 'tools/publish/SysAdminSuite.DashboardHost'
New-Item -ItemType Directory -Force -Path $toolsPublish | Out-Null
Copy-Item -LiteralPath $technicalPath -Destination (Join-Path $toolsPublish $technicalName) -Force

Write-Host ""
Write-Host "Published:"
Write-Host "  $friendlyPath"
Write-Host "  $technicalPath"
Write-Host "  $(Join-Path $toolsPublish $technicalName)"
Write-Host ""
Write-Host "Field users can double-click:"
Write-Host "  START-HERE-SysAdminSuite-Dashboard.bat"
Write-Host ""
Write-Host "Requires .NET 8 runtime on the workstation."
