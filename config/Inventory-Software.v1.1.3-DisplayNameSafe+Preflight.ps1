<# Inventory-Software.v1.1.3-DisplayNameSafe+Preflight.ps1
CHANGES:
- Document & fix: $Host collision ($host → $TargetHost) and $PSScriptRoot misuse (use context resolver).
- Keep superset fix: filter files first; never touch .Path on CSV rows.
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

# NOTE: $PSScriptRoot is ONLY defined when a script/module is executing.
# Do not rely on it from the console. This resolver finds the suite root
# from (a) $PSCommandPath, (b) $PSScriptRoot, (c) VS Code editor file, (d) cwd.
function Resolve-SASContext {
  param(
    [string]$PreferredRepoRoot,
    [string]$PreferredRepoHost
  )

  $anchor =
    if     ($PSCommandPath) { Split-Path -Parent $PSCommandPath }
    elseif ($PSScriptRoot)  { $PSScriptRoot }
    elseif ($psEditor -and $psEditor.GetEditorContext()) {
      Split-Path -Parent ($psEditor.GetEditorContext().CurrentFile.Path)
    }
    else { (Get-Location).Path }

  # Walk upward until we find a folder that contains 'config' (suite root)
  $cur = Get-Item -LiteralPath $anchor
  while ($cur -and -not (Test-Path (Join-Path $cur.FullName 'config'))) { $cur = $cur.Parent }
  if (-not $cur) { throw "Could not resolve SysAdminSuite root from '$anchor'." }

  $SASRoot    = $cur.FullName
  $ConfigRoot = Join-Path $SASRoot 'config'

  # RepoRoot priority: explicit > env > \\host\share > sibling SoftwareRepo > C:\SoftwareRepo
  $ResolvedRepoRoot =
    if     ($PreferredRepoRoot) { $PreferredRepoRoot }
    elseif ($env:REPO_ROOT)     { $env:REPO_ROOT }
    elseif ($PreferredRepoHost) { "\\$PreferredRepoHost\SoftwareRepo" }
    elseif (Test-Path (Join-Path $SASRoot 'SoftwareRepo')) { Join-Path $SASRoot 'SoftwareRepo' }
    else { 'C:\SoftwareRepo' }

  foreach($p in @($ResolvedRepoRoot, (Join-Path $ResolvedRepoRoot 'inventory'))) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
  }

  [pscustomobject]@{
    SASRoot    = $SASRoot
    ConfigRoot = $ConfigRoot
    RepoRoot   = $ResolvedRepoRoot
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
    # Guarantee expected columns so StrictMode won’t bark later
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

function TryVersion { param([string]$v) try { [version]$v } catch { $null } }

function Pick-Best {
  <#
    Prefers highest parsable [version], else first row with Version, else first row.
  #>
  param([Parameter(Mandatory)][object[]]$Rows)
  $withParsed = foreach($r in $Rows) { [pscustomobject]@{ Row = $r; Parsed = (TryVersion $r.Version) } }
  $candidates = $withParsed | Where-Object Parsed | Sort-Object Parsed -Descending
  if ($candidates) { return $candidates[0].Row }
  $withVer = $Rows | Where-Object Version
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
