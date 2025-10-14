<# Inventory-Software.v1.1.2-DisplayNameSafe+Preflight.ps1
CHANGES:
- Fix superset merge (filter on FileInfo.FullName pre-import; no 'Path' on data rows).
- Hardened StrictMode + Preflight; context-aware RepoRoot; null-safe merge + HTML.
#>

[CmdletBinding()]
param(
  [string[]]$ComputerName = @($env:COMPUTERNAME),
  [string]  $RepoHost     = $env:REPO_HOST,
  [string]  $RepoRoot,
  [switch]  $NoMerge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#--------------------------- helpers ------------------------------------------#

function Resolve-SASContext {
  param(
    [string]$PreferredRepoRoot,
    [string]$PreferredRepoHost
  )

  # Anchor: script > module > VSCode editor > console
  $anchor =
    if     ($PSCommandPath) { Split-Path -Parent $PSCommandPath }
    elseif ($PSScriptRoot)  { $PSScriptRoot }
    elseif ($psEditor -and $psEditor.GetEditorContext()) {
      Split-Path -Parent ($psEditor.GetEditorContext().CurrentFile.Path)
    }
    else { (Get-Location).Path }

  # Walk upward until we find a folder containing 'config' (suite root)
  $cur = Get-Item -LiteralPath $anchor
  while ($cur -and -not (Test-Path (Join-Path $cur.FullName 'config'))) { $cur = $cur.Parent }
  if (-not $cur) { throw "Could not resolve SysAdminSuite root from '$anchor'." }

  $SASRoot    = $cur.FullName
  $ConfigRoot = Join-Path $SASRoot 'config'

  # RepoRoot priority: explicit > env > \\host\share > sibling SoftwareRepo > C:\SoftwareRepo
  $RepoRoot =
    if     ($PreferredRepoRoot) { $PreferredRepoRoot }
    elseif ($env:REPO_ROOT)     { $env:REPO_ROOT }
    elseif ($PreferredRepoHost) { "\\$PreferredRepoHost\SoftwareRepo" }
    elseif (Test-Path (Join-Path $SASRoot 'SoftwareRepo')) { Join-Path $SASRoot 'SoftwareRepo' }
    else { 'C:\SoftwareRepo' }

  foreach($p in @($RepoRoot, (Join-Path $RepoRoot 'inventory'))) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
  }

  [pscustomobject]@{
    SASRoot    = $SASRoot
    ConfigRoot = $ConfigRoot
    RepoRoot   = $RepoRoot
  }
}

function Ensure-Directory {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -Path $Path -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Normalize-Row {
  param([Parameter(Mandatory,ValueFromPipeline)][object]$Row, [string]$Host)
  process {
    $need = 'Name','Version','Publisher','UninstallString','InstallLocation','DisplayName','DisplayVersion','Host','DetectType','DetectValue','InstallDate','Timestamp'
    foreach ($c in $need) {
      if (-not ($Row.PSObject.Properties.Name -contains $c)) {
        $Row | Add-Member -NotePropertyName $c -NotePropertyValue $null
      }
    }
    if (-not $Row.Name)       { $Row.Name       = $Row.DisplayName }
    if (-not $Row.Version)    { $Row.Version    = $Row.DisplayVersion }
    if (-not $Row.Host)       { $Row.Host       = $Host }
    if (-not $Row.Timestamp)  { $Row.Timestamp  = (Get-Date).ToString('s') }
    return $Row
  }
}

function TryVersion {
  param([string]$v)
  try { return [version]$v } catch { return $null }
}

function Pick-Best {
  param([Parameter(Mandatory)][object[]]$Rows)
  $withParsed = foreach($r in $Rows) {
    [pscustomobject]@{ Row = $r; Parsed = (TryVersion $r.Version) }
  }
  $candidates = $withParsed | Where-Object { $_.Parsed } | Sort-Object Parsed -Descending
  if ($candidates) { return $candidates[0].Row }
  $withVer = $Rows | Where-Object { $_.Version }
  if ($withVer) { return $withVer[0] }
  return $Rows[0]
}

#--------------------------- preflight ----------------------------------------#

$ctx = Resolve-SASContext -PreferredRepoRoot $RepoRoot -PreferredRepoHost $RepoHost
$resolvedRepoRoot = $ctx.RepoRoot
$inventoryRoot    = Join-Path $resolvedRepoRoot 'inventory'
Ensure-Directory -Path $inventoryRoot
Write-Host ("Using RepoRoot: {0}" -f $resolvedRepoRoot) -ForegroundColor Cyan

# Registry locations to enumerate for installed software
$arpRoots = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

# Collector runs locally or remotely to gather ARP rows
$collector = {
  param([string[]]$arpRoots, [string]$TargetHost)
  $ErrorActionPreference = 'SilentlyContinue'
  $rows = foreach ($root in $arpRoots) {
    Get-ChildItem -Path $root | ForEach-Object {
      $p = $_.PSPath
      $it = Get-ItemProperty -Path $p
      if ($null -ne $it.DisplayName -and "$($it.DisplayName)".Trim() -ne '') {
        [pscustomobject]@{
          Name            = "$($it.DisplayName)".Trim()
          Version         = "$($it.DisplayVersion)".Trim()
          Publisher       = "$($it.Publisher)".Trim()
          UninstallString = "$($it.UninstallString)".Trim()
          InstallLocation = "$($it.InstallLocation)".Trim()
          InstallDate     = "$($it.InstallDate)".Trim()
          DetectType      = 'RegKey'
          DetectValue     = $_.Name
          Host            = $TargetHost
          Timestamp       = (Get-Date).ToString('s')
        }
      }
    }
  }
  $rows
}

#--------------------------- per-host export ----------------------------------#

$perHostCsvs = @()

foreach ($c in $ComputerName) {
  $TargetHost = $c
  $hostDir = Join-Path $inventoryRoot $TargetHost
  Ensure-Directory -Path $hostDir
  $csv = Join-Path $hostDir ("installed_software_{0}.csv" -f $TargetHost)
  $html = [IO.Path]::ChangeExtension($csv, '.html')

  $data =
    if ($TargetHost -in @('localhost','127.0.0.1',$env:COMPUTERNAME)) {
      & $collector -arpRoots $arpRoots -TargetHost $TargetHost
    } else {
      Invoke-Command -ComputerName $TargetHost -ScriptBlock $collector -ArgumentList (,$arpRoots),$TargetHost
    }

  $norm = $data | Normalize-Row -Host $TargetHost
  $norm | Sort-Object Name | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
  $norm | Select-Object Name,Version,Publisher,Host | Sort-Object Name |
    ConvertTo-Html -Title "Installed Software - $TargetHost" |
    Set-Content -Path $html -Encoding UTF8

  $perHostCsvs += $csv
  Write-Host ("Wrote {0} items => {1}" -f ($norm.Count), $csv) -ForegroundColor Green
}

#--------------------------- superset merge -----------------------------------#

if (-not $NoMerge) {
  $csvFiles = Get-ChildItem -Path (Join-Path $inventoryRoot '*\installed_software_*.csv') -File -ErrorAction SilentlyContinue

  $rows = foreach ($f in $csvFiles) {
    try {
      $r = Import-Csv -Path $f.FullName
      foreach ($x in $r) {
        if (-not ($x.PSObject.Properties.Name -contains 'SourceCsv')) {
          $x | Add-Member -NotePropertyName 'SourceCsv' -NotePropertyValue $f.FullName
        } else { $x.SourceCsv = $f.FullName }
        $x
      }
    } catch {
      Write-Warning "Failed to import $($f.FullName): $($_.Exception.Message)"
    }
  }

  $rows = $rows | Normalize-Row -Host '<unknown>'

  $superset =
    $rows |
    Group-Object -Property Name, Publisher |
    ForEach-Object { Pick-Best -Rows $_.Group }

  $supCsv = Join-Path $inventoryRoot 'software_superset.csv'
  $superset | Sort-Object Name | Export-Csv -Path $supCsv -NoTypeInformation -Encoding UTF8
  Write-Host "Wrote superset => $supCsv" -ForegroundColor Green
}

Write-Host "Inventory complete." -ForegroundColor Green


