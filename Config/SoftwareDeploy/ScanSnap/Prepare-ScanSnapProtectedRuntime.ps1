#Requires -Version 5.1
<#
.SYNOPSIS
  Seal the qualified ScanSnap installer + response file into an already-prepared C:\SASAL runtime.

.DESCRIPTION
  This is an Internet/Guest preparation-phase operation. It performs no target contact and
  no public-network operation itself. The tracked runtime must already have been prepared
  by the repository-owned Guest -> protected runtime flow.

  The script verifies the existing tracked-file seal, proves the source package manifest
  matches the sealed runtime manifest, verifies the bound installer SHA-256, copies only
  the qualified EXE and matching ISS into the runtime's ignored installer directory,
  verifies source/target SHA-256 equality, and writes a machine-local receipt.

  Live protected ScanSnap deployment consumes this receipt and re-verifies the tracked
  runtime seal plus package hashes before target contact.
#>
[CmdletBinding()]
param(
  [string]$SourcePackageRoot = $PSScriptRoot,
  [string]$RuntimeRoot = 'C:\SASAL',
  [string]$ReceiptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SsSha256([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File missing: $Path" }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Invoke-SsRuntimeSeal {
  param([string]$Root,[string]$ExpectedCommit)
  $sealScript = Join-Path $Root 'scripts\Test-SasAutoLogonRuntimeSeal.ps1'
  if (-not (Test-Path -LiteralPath $sealScript -PathType Leaf)) {
    throw "Runtime seal validator missing: $sealScript"
  }
  $args = @(
    '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$sealScript,
    '-RuntimeRoot',$Root,
    '-ExpectedCommit',$ExpectedCommit
  )
  & powershell.exe @args
  if ($LASTEXITCODE -ne 0) {
    throw "Tracked runtime seal verification failed with exit code $LASTEXITCODE."
  }
}

$sourcePackage = (Resolve-Path -LiteralPath $SourcePackageRoot).Path
$runtime = (Resolve-Path -LiteralPath $RuntimeRoot).Path
$runtimePackage = Join-Path $runtime 'Config\SoftwareDeploy\ScanSnap'
$sourceManifestPath = Join-Path $sourcePackage 'package.manifest.json'
$runtimeManifestPath = Join-Path $runtimePackage 'package.manifest.json'
$runtimeStatePath = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\autologon-short-runtime.json'
if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
  $ReceiptPath = Join-Path $env:ProgramData 'SysAdminSuite\ScanSnap\protected-runtime-package.json'
}

foreach ($required in @($sourceManifestPath,$runtimeManifestPath,$runtimeStatePath)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required preparation artifact missing: $required" }
}
$runtimeState = Get-Content -LiteralPath $runtimeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
$preparedCommit = ([string]$runtimeState.prepared_commit).Trim()
if ([string]::IsNullOrWhiteSpace($preparedCommit)) { throw 'Prepared runtime manifest has no prepared_commit.' }

# Prove tracked code/runtime before copying ignored package payloads.
Invoke-SsRuntimeSeal -Root $runtime -ExpectedCommit $preparedCommit

$sourceManifestHash = Get-SsSha256 -Path $sourceManifestPath
$runtimeManifestHash = Get-SsSha256 -Path $runtimeManifestPath
if ($sourceManifestHash -ne $runtimeManifestHash) {
  throw "Source ScanSnap manifest does not match sealed runtime manifest. source=$sourceManifestHash runtime=$runtimeManifestHash"
}

$manifest = Get-Content -LiteralPath $sourceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not [bool]$manifest.Bound) { throw 'ScanSnap package manifest is not bound.' }
$installerName = [string]$manifest.InstallerFileName
if ([string]::IsNullOrWhiteSpace($installerName)) { throw 'InstallerFileName is empty.' }
$issName = [IO.Path]::ChangeExtension($installerName,'.iss')
$sourceInstaller = Join-Path (Join-Path $sourcePackage 'installers') $installerName
$sourceIss = Join-Path (Join-Path $sourcePackage 'installers') $issName
$sourceInstallerHash = Get-SsSha256 -Path $sourceInstaller
$sourceIssHash = Get-SsSha256 -Path $sourceIss
if ($sourceInstallerHash -ne ([string]$manifest.Sha256).ToUpperInvariant()) {
  throw "Qualified installer SHA-256 mismatch. manifest=$($manifest.Sha256) actual=$sourceInstallerHash"
}
if ([string]$manifest.SilentArgs -notmatch [regex]::Escape($issName)) {
  throw "SilentArgs do not bind the expected response file: $issName"
}

$runtimeInstallerDir = Join-Path $runtimePackage 'installers'
New-Item -ItemType Directory -Path $runtimeInstallerDir -Force | Out-Null
$runtimeInstaller = Join-Path $runtimeInstallerDir $installerName
$runtimeIss = Join-Path $runtimeInstallerDir $issName
$receiptDir = Split-Path -Parent $ReceiptPath
New-Item -ItemType Directory -Path $receiptDir -Force | Out-Null
if (Test-Path -LiteralPath $ReceiptPath -PathType Leaf) { Remove-Item -LiteralPath $ReceiptPath -Force }

# Stage to temporary siblings first so an interrupted copy cannot leave a valid receipt.
$tmpInstaller = "$runtimeInstaller.preparing"
$tmpIss = "$runtimeIss.preparing"
foreach ($tmp in @($tmpInstaller,$tmpIss)) {
  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
}
Copy-Item -LiteralPath $sourceInstaller -Destination $tmpInstaller -Force
Copy-Item -LiteralPath $sourceIss -Destination $tmpIss -Force
if ((Get-SsSha256 -Path $tmpInstaller) -ne $sourceInstallerHash) { throw 'Runtime installer copy hash mismatch.' }
if ((Get-SsSha256 -Path $tmpIss) -ne $sourceIssHash) { throw 'Runtime ISS copy hash mismatch.' }
Move-Item -LiteralPath $tmpInstaller -Destination $runtimeInstaller -Force
Move-Item -LiteralPath $tmpIss -Destination $runtimeIss -Force

$runtimeInstallerHash = Get-SsSha256 -Path $runtimeInstaller
$runtimeIssHash = Get-SsSha256 -Path $runtimeIss
if ($runtimeInstallerHash -ne $sourceInstallerHash -or $runtimeIssHash -ne $sourceIssHash) {
  throw 'Runtime package verification failed after final placement.'
}

$receipt = [pscustomobject][ordered]@{
  schema_version = 'scansnap-protected-runtime-package/v1'
  created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  status = 'PASS'
  classification = 'SCANSNAP_PROTECTED_RUNTIME_READY'
  runtime_root = $runtime
  runtime_package_root = $runtimePackage
  prepared_commit = $preparedCommit
  package_manifest_sha256 = $runtimeManifestHash
  installer = [ordered]@{
    name = $installerName
    manifest_sha256 = ([string]$manifest.Sha256).ToUpperInvariant()
    source_sha256 = $sourceInstallerHash
    runtime_sha256 = $runtimeInstallerHash
  }
  companion = [ordered]@{
    name = $issName
    source_sha256 = $sourceIssHash
    runtime_sha256 = $runtimeIssHash
  }
  tracked_runtime_seal_verified = $true
  runtime_git_transport = 'LOCAL_FILESYSTEM_ONLY'
  network_activity_performed = $false
  target_contact_performed = $false
  target_mutation_performed = $false
}
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
Write-Host "SCANSNAP_PROTECTED_RUNTIME_READY receipt=$ReceiptPath commit=$preparedCommit" -ForegroundColor Green
exit 0
