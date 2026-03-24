<#
Build-FetchMap.ps1 - resolves versions and URLs into fetch-map.csv for the hardened fetcher.
- Supports Source=github (Repo "owner/name") or Source=url.
- Strategy = latest | pinned
- Uses AssetRegex to choose a GitHub release asset.
#>

[CmdletBinding()]
param(
  [string]$SourcesCsv = ".\sources.csv",
  [string]$OutCsv     = ".\fetch-map.csv",
  [string]$RepoRoot   = $(if ($env:REPO_ROOT) { $env:REPO_ROOT } else { Join-Path $PSScriptRoot 'SoftwareRepo' }), # optional: write directly there
  [string[]]$AllowList = @("api.github.com","github.com","objects.githubusercontent.com","dl.google.com","download.visualstudio.microsoft.com","aka.ms","python.org","www.python.org","obsidian.md","githubusercontent.com"),
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
function Fail($m){ Write-Error $m; exit 2 }
function Info($m){ Write-Host $m -ForegroundColor Cyan }
function Good($m){ Write-Host $m -ForegroundColor Green }

if (!(Test-Path $SourcesCsv)) { Fail "Missing sources file: $SourcesCsv" }
$src = Import-Csv $SourcesCsv

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-GitHubRelease {
  param([string]$Repo, [string]$Strategy, [string]$Version)
  $base = "https://api.github.com/repos/$Repo/releases"
  $ua = "SysAdminSuite-Resolve/1.0 (+PowerShell)"

  if ($Strategy -eq 'latest') {
    Invoke-RestMethod -Uri "$base/latest" -Headers @{ 'User-Agent'=$ua } -ErrorAction Stop
  } elseif ($Strategy -eq 'pinned' -and $Version) {
    Invoke-RestMethod -Uri "$base/tags/$Version" -Headers @{ 'User-Agent'=$ua } -ErrorAction Stop
  } else {
    Fail "Invalid GitHub Strategy/Version for $Repo ($Strategy / $Version)"
  }
}

function AllowedHost([string]$url, [string[]]$extra){
  $h = ([uri]$url).Host.ToLower()
  foreach($d in ($AllowList + $extra)){
    if ($null -eq $d -or $d -eq "") { continue }
    $t = $d.ToLower()
    if ($h -eq $t -or $h.EndsWith(".$t")) { return $true }
  }
  return $false
}

$rows = @()

foreach($r in $src){
  $name  = $r.Name
  $srcTy = ($r.Source ?? 'url').ToLower()
  $strat = ($r.Strategy ?? 'pinned').ToLower()
  $ver   = $r.Version
  $url   = $null
  $file  = $null

  switch ($srcTy) {
    'github' {
      if (-not $r.Repo) { Fail "Row '$name': Repo required for Source=github" }
      $rel = Get-GitHubRelease -Repo $r.Repo -Strategy $strat -Version $ver
      $match = $rel.assets | Where-Object { $_.name -match $r.AssetRegex }
      if (-not $match)   { Fail "Row '$name': no asset matched '$($r.AssetRegex)' in $($r.Repo) [$($rel.tag_name)]" }
      $asset = $match | Select-Object -First 1
      $url   = $asset.browser_download_url
      $file  = if ($r.FileNameTemplate -and $r.FileNameTemplate -match '{{version}}') {
                 $r.FileNameTemplate -replace '\{\{version\}\}', $rel.tag_name.TrimStart('v')
               } elseif ($r.FileNameTemplate -and $r.FileNameTemplate -ne '') {
                 $r.FileNameTemplate
               } else {
                 $asset.name
               }
    }
    'url' {
      $tmpl = $r.UrlTemplate
      if (-not $tmpl -and $r.Url) { $tmpl = $r.Url }  # optional Url passthrough
      if (-not $tmpl) { Fail "Row '$name': UrlTemplate (or Url) required for Source=url" }
      if ((($tmpl -match '\{\{version\}\}') -or ($r.FileNameTemplate -match '\{\{version\}\}')) -and [string]::IsNullOrEmpty($ver)) {
        Fail "Row '$name': Version is required because template contains {{version}}."
      }
      $resolvedVer = $ver
      $url  = ($tmpl -replace '\{\{version\}\}', $resolvedVer)
      $file = ($r.FileNameTemplate) ? ($r.FileNameTemplate -replace '\{\{version\}\}', $resolvedVer) : (Split-Path $url -Leaf)
    }
    default { Fail "Row '$name': Unknown Source '$srcTy'" }
  }

  if (-not (AllowedHost $url ($r.AllowDomains -split ';'))) {
    Fail "Row '$name': URL host blocked by allow-list -> $url"
  }

  $rows += [pscustomobject]@{
    Name         = $name
    Url          = $url
    FileName     = $file
    Type         = $r.Type
    SilentArgs   = $r.SilentArgs
    DetectType   = $r.DetectType
    DetectValue  = $r.DetectValue
    AddToPath    = $r.AddToPath
    PostInstall  = $r.PostInstall
    AllowDomains = $r.AllowDomains
  }
}

$target = $OutCsv
if ($RepoRoot -and (Test-Path $RepoRoot)) {
  $target = Join-Path $RepoRoot "fetch-map.csv"
}

if ($WhatIf) {
  Info "WHATIF: would write $($rows.Count) entries to $target"
  $rows | Format-Table Name, Url, FileName, Type -Auto
  exit
}

$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $target
Good "fetch-map.csv written: $target"