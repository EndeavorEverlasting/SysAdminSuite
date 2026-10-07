#Requires -Version 5.1
<#
.SYNOPSIS
  Bind an operator-provided ScanSnap installer into package.manifest.json.

.DESCRIPTION
  Fingerprints type and SHA256 from the real file. Does NOT invent SilentArgs
  or DetectValue — the operator must supply those from package evidence.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$InstallerPath,

  [Parameter(Mandatory)]
  [string]$SilentArgs,

  [Parameter(Mandatory)]
  [ValidateSet('file', 'regkey')]
  [string]$DetectType,

  [Parameter(Mandatory)]
  [string]$DetectValue,

  [ValidateSet('msi', 'exe', '')]
  [string]$Type = '',

  [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ManifestPath) {
  $ManifestPath = Join-Path $packageRoot 'package.manifest.json'
}
$installersDir = Join-Path $packageRoot 'installers'
New-Item -ItemType Directory -Force -Path $installersDir | Out-Null

if (-not (Test-Path -LiteralPath $InstallerPath)) {
  throw "Installer not found: $InstallerPath"
}

$item = Get-Item -LiteralPath $InstallerPath
$destName = $item.Name
$destPath = Join-Path $installersDir $destName
$destResolved = $null
if (Test-Path -LiteralPath $destPath) {
  $destResolved = (Resolve-Path -LiteralPath $destPath).Path
}
if ($item.FullName -ne $destResolved) {
  Copy-Item -LiteralPath $item.FullName -Destination $destPath -Force
}

function Guess-SsInstallerType {
  param([string]$Path)
  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($ext -eq '.msi') { return 'msi' }
  $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
  try {
    $buf = New-Object byte[] 8192
    [void]$fs.Read($buf, 0, $buf.Length)
    $txt = [Text.Encoding]::ASCII.GetString($buf)
    if ($txt -match 'Inno Setup') { return 'exe' }
    if ($txt -match 'Nullsoft') { return 'exe' }
    if ($txt -match 'InstallShield') { return 'exe' }
    return 'exe'
  } finally {
    $fs.Close()
  }
}

if ([string]::IsNullOrWhiteSpace($Type)) {
  $Type = Guess-SsInstallerType -Path $destPath
}

if ([string]::IsNullOrWhiteSpace($SilentArgs)) {
  throw 'SilentArgs is mandatory. Do not invent switches; supply evidenced silent arguments.'
}
if ([string]::IsNullOrWhiteSpace($DetectValue)) {
  throw 'DetectValue is mandatory. Installation success requires a detection gate.'
}

$sha = (Get-FileHash -LiteralPath $destPath -Algorithm SHA256).Hash.ToUpperInvariant()

$manifest = [ordered]@{
  ProductName                     = 'ScanSnap'
  InstallerFileName               = $destName
  Sha256                          = $sha
  Type                            = $Type
  SilentArgs                      = $SilentArgs
  DetectType                      = $DetectType
  DetectValue                     = $DetectValue
  Bound                           = $true
  BoundAtUtc                      = (Get-Date).ToUniversalTime().ToString('o')
  BoundBy                         = ("{0}\{1}@{2}" -f $env:USERDOMAIN, $env:USERNAME, $env:COMPUTERNAME)
  TaskName                        = 'SysAdminSuite_ScanSnap_Install'
  RemoteStageRelativePath         = 'SoftwareRepo\ScanSnap'
  RemoteProgramDataRelativePath   = 'ProgramData\SysAdminSuite\SoftwareDeploy\ScanSnap'
  Notes                           = 'Bound from operator-provided installer. SilentArgs/DetectValue were supplied explicitly — not invented by type fingerprinting.'
}

($manifest | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
Write-Host "Bound package -> $ManifestPath" -ForegroundColor Green
Write-Host "InstallerFileName=$destName"
Write-Host "Sha256=$sha"
Write-Host "Type=$Type"
Write-Host "SilentArgs=$SilentArgs"
Write-Host "Detect=$DetectType : $DetectValue"
