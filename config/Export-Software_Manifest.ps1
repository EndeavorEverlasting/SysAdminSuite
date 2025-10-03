<#
Export-Software_Manifest.ps1
Creates a manifest-style packages_draft.csv without winget.
#>

param(
  [string]$OutDir = "$PSScriptRoot\exports",
  [string]$RepoRoot = "\\LPW003ASI037\C$\SoftwareRepo",  # optional: if present, copy draft there too
  [switch]$CopyToRepo
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Collect HKLM ARP (32/64)
$arpRoots = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

$rows = foreach ($root in $arpRoots) {
  Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    if ($p.DisplayName) {
      [PSCustomObject]@{
        DisplayName     = [string]$p.DisplayName
        DisplayVersion  = [string]$p.DisplayVersion
        Publisher       = [string]$p.Publisher
        InstallLocation = [string]$p.InstallLocation
        UninstallString = [string]$p.UninstallString
        QuietUninstall  = [string]$p.QuietUninstallString
        ProductCode     = [string]$p.PSChildName  # many MSIs use GUID here
        RegistryPath    = $_.PSPath
      }
    }
  }
}

# Dedup by DisplayName (keep row with the "largest" version text)
$rows = $rows | Sort-Object DisplayName, DisplayVersion -Descending `
  | Group-Object DisplayName `
  | ForEach-Object { $_.Group | Select-Object -First 1 }

function Suggest-DetectTypeValue {
  param([pscustomobject]$r)
  # Prefer MSI product code (GUID-like)
  $pc = $r.ProductCode
  if ($pc -and $pc -match '^\{?[0-9A-Fa-f-]{32,}\}?$') {
    return ,@('productcode', $pc)
  }
  # Next best: the ARP key
  if ($r.RegistryPath) {
    $reg = $r.RegistryPath -replace '^Registry::','' -replace 'HKLM:\\','HKLM\'
    return ,@('regkey', $reg)
  }
  # Fallback: file placeholder under InstallLocation
  if ($r.InstallLocation) {
    $path = ($r.InstallLocation.TrimEnd('\') + '\<exe>').Replace('\\\\','\')
    return ,@('file', $path)
  }
  return ,@('regkey','HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
}

$manifest = foreach($r in $rows){
  $det = Suggest-DetectTypeValue $r
  [pscustomobject]@{
    Name         = $r.DisplayName
    InstallerFile= ''              # you fill this
    Type         = ''              # msi|exe|zip|msix
    SilentArgs   = ''              # /qn /norestart, /S, etc.
    DetectType   = $det[0]
    DetectValue  = $det[1]
    PostInstall  = ''
    AddToPath    = ''
    _Publisher   = $r.Publisher
  }
}

# Make it easy to read: sort by publisher then name
$manifest = $manifest | Sort-Object _Publisher, Name

# Save locally
$localOut = Join-Path $OutDir 'packages_draft.csv'
$manifest | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $localOut
Write-Host "Draft written: $localOut" -ForegroundColor Green

# Optional: copy into repo
if ($CopyToRepo) {
  if (Test-Path $RepoRoot) {
    $repoDraft = Join-Path $RepoRoot 'packages_draft.csv'
    Copy-Item $localOut $repoDraft -Force
    Write-Host "Draft copied to repo: $repoDraft" -ForegroundColor Green
  } else {
    Write-Warning "RepoRoot not found: $RepoRoot  (nothing copied)"
  }
}
