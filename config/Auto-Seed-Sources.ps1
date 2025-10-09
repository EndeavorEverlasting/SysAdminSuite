<#  Auto-Seed-Sources.ps1
    Detects common engineering apps on *this* machine and appends
    robust vendor/GitHub source rows to sources.csv (no duplicates).
    Then (optionally) rebuilds fetch-map.csv so you're ready to test/fetch.

    Supported detections (initial set):
      - Google Chrome (Enterprise MSI)
      - Mozilla Firefox (Enterprise MSI)
      - .NET (Hosting bundle + Desktop runtime) via official metadata JSON
      - Python 3.x (amd64 installer)
      - Cursor (latest stable, redirect-safe)
      - Anki (GitHub ankitects/anki)
      - Git for Windows (GitHub git-for-windows/git)
      - GitHub CLI (GitHub cli/cli)
      - PowerShell 7 (GitHub PowerShell/PowerShell)

    Requires: GoLiveTools.ps1 in the same folder; PowerShell 7+
#>

param(
  [string]$RepoHost = $env:REPO_HOST,               # optional; falls back to C:\SoftwareRepo via GoLiveTools
  [switch]$Rebuild,                                  # also run Rebuild-FetchMap at the end
  [switch]$WhatIf                                    # show would-be changes without writing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---- bootstrap and repo resolution -------------------------------------------------
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools  = Join-Path $here 'GoLiveTools.ps1'
if (-not (Test-Path $tools)) { throw "Missing GoLiveTools.ps1 at $tools" }
. $tools -RepoHost $RepoHost   # prints banner + preflight, exposes $RepoRoot

# ---- helpers ----------------------------------------------------------------------
function Get-ArpRows {
  $roots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  foreach($r in $roots){
    Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object {
      $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
      if ($p.DisplayName){
        [pscustomobject]@{
          Name    = [string]$p.DisplayName
          Version = [string]$p.DisplayVersion
          Pub     = [string]$p.Publisher
          RegPath = $_.PSPath
        }
      }
    }
  }
}

function Has-App([string]$regex, [ref]$hitVersion){
  $row = Get-ArpRows | Where-Object { $_.Name -match $regex } | Sort-Object Version -Descending | Select-Object -First 1
  if ($row){ $hitVersion.Value = $row.Version; return $true } else { return $false }
}

function Ensure-File([string]$path){
  if (-not (Test-Path $path)) {
    New-Item -ItemType File -Force -Path $path | Out-Null
  }
}

# Build a CSV row object with canonical columns
function New-SourceRow {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][ValidateSet('url','github')][string]$Source,
    [string]$Repo,
    [ValidateSet('latest','pinned')][string]$Strategy = 'pinned',
    [string]$Version,
    [string]$UrlTemplate,
    [string]$AssetRegex,
    [string]$FileNameTemplate,
    [string]$Type,
    [string]$SilentArgs,
    [string]$DetectType,
    [string]$DetectValue,
    [string]$AddToPath,
    [string]$PostInstall,
    [string]$AllowDomains
  )
  [pscustomobject]@{
    Name=$Name; Source=$Source; Repo=$Repo; Strategy=$Strategy; Version=$Version;
    UrlTemplate=$UrlTemplate; AssetRegex=$AssetRegex; FileNameTemplate=$FileNameTemplate;
    Type=$Type; SilentArgs=$SilentArgs; DetectType=$DetectType; DetectValue=$DetectValue;
    AddToPath=$AddToPath; PostInstall=$PostInstall; AllowDomains=$AllowDomains
  }
}

# Pull latest .NET payload URLs from official metadata
function Get-DotNetLatest {
  param([ValidateSet('6.0','7.0','8.0')][string]$Major='8.0')
  $meta = Invoke-RestMethod "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/$Major/releases.json"
  $latest = $meta.releases | Where-Object { $_.security } | Select-Object -First 1
  if (-not $latest) { $latest = $meta.releases | Select-Object -First 1 }
  return $latest
}

# ---- seed logic -------------------------------------------------------------------
$csvPath = Join-Path $RepoRoot 'sources.csv'
Ensure-File $csvPath
$existing = if (Test-Path $csvPath -and (Get-Content $csvPath -TotalCount 1)) { Import-Csv $csvPath } else { @() }

$addRows = @()
$ver = $null

# 1) Chrome (Enterprise MSI)
if (Has-App 'Google Chrome' ([ref]$ver)) {
  $addRows += New-SourceRow -Name 'Google Chrome' -Source url -Strategy latest `
    -UrlTemplate 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' `
    -Type 'msi' -SilentArgs '/qn /norestart' `
    -DetectType 'regkey' -DetectValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome'
}

# 2) Firefox (Enterprise MSI)
if (Has-App 'Mozilla Firefox' ([ref]$ver)) {
  $addRows += New-SourceRow -Name 'Mozilla Firefox' -Source url -Strategy latest `
    -UrlTemplate 'https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=en-US' `
    -Type 'msi' -SilentArgs '/qn /norestart' `
    -DetectType 'file' -DetectValue 'C:\Program Files\Mozilla Firefox\firefox.exe'
}

# 3) .NET (Hosting bundle + Desktop Runtime) – latest secure for 8.0
try {
  $dn = Get-DotNetLatest -Major '8.0'
  $host = $dn.windowsdesktop | Out-Null  # intentional touch to ensure object
  # Hosting bundle & Desktop runtime links live under release JSON assets:
  $hosting = ($dn.aspnetcore.runtime.windowsdesktop | Out-Null)
} catch {
  # Older schema fallback
}

# Better: explicitly search assets list
try{
  $assets = $dn.sdks, $dn.runtime, $dn.aspnetcore_runtime, $dn.windowsdesktop `
            | ForEach-Object { $_ } | Where-Object { $_ -ne $null } | ForEach-Object { $_.files } | ForEach-Object { $_ } `
            | Where-Object { $_.rid -like '*win*' -and $_.url -match '^https?://'}
  $desktop = $assets | Where-Object { $_.name -match 'windowsdesktop-runtime-.*-win-x64\.exe$' } | Select-Object -First 1
  $hosting = $assets | Where-Object { $_.name -match 'dotnet-hosting-.*-win\.exe$' } | Select-Object -First 1
  if ($desktop) {
    $addRows += New-SourceRow -Name '.NET Desktop Runtime (x64)' -Source url -Strategy pinned -Version $dn.releaseVersion `
      -UrlTemplate $desktop.url -Type 'exe' -SilentArgs '/install /quiet /norestart' `
      -DetectType 'regkey' -DetectValue 'HKLM\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedhost'
  }
  if ($hosting) {
    $addRows += New-SourceRow -Name '.NET Hosting Bundle' -Source url -Strategy pinned -Version $dn.releaseVersion `
      -UrlTemplate $hosting.url -Type 'exe' -SilentArgs '/install /quiet /norestart' `
      -DetectType 'regkey' -DetectValue 'HKLM\SOFTWARE\Microsoft\AspNetCore\Shared Framework'
  }
} catch {}

# 4) Python 3.x (from python.org)
if (Has-App '^Python 3\.' ([ref]$ver)) {
  # Normal python.org naming: https://www.python.org/ftp/python/<ver>/python-<ver>-amd64.exe
  $verTrim = ($ver -replace '[^\d\.]').Trim()
  if ($verTrim) {
    $tmpl = "https://www.python.org/ftp/python/$verTrim/python-$verTrim-amd64.exe"
    $addRows += New-SourceRow -Name "Python $verTrim (amd64)" -Source url -Strategy pinned -Version $verTrim `
      -UrlTemplate $tmpl -Type 'exe' -SilentArgs '/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=1' `
      -DetectType 'file' -DetectValue 'C:\Program Files\Python*\python.exe'
  }
}

# 5) Cursor (latest, redirect-safe)
if (Has-App '^Cursor$' ([ref]$ver)) {
  # Vendor provides a stable "latest" endpoint that redirects
  $addRows += New-SourceRow -Name 'Cursor' -Source url -Strategy latest `
    -UrlTemplate 'https://downloader.cursor.sh/windows/nsis/x64' `
    -Type 'exe' -SilentArgs '/S' `
    -DetectType 'file' -DetectValue 'C:\Users\*\AppData\Local\Programs\Cursor\Cursor.exe'
}

# 6) Anki (GitHub releases)
if (Has-App '^Anki' ([ref]$ver)) {
  $addRows += New-SourceRow -Name 'Anki (Qt6, Windows)' -Source github -Repo 'ankitects/anki' -Strategy latest `
    -AssetRegex 'anki-.*-windows-qt6\.exe' -FileNameTemplate '{{asset}}' `
    -Type 'exe' -SilentArgs '/S' `
    -DetectType 'file' -DetectValue 'C:\Program Files\Anki\anki.exe'
}

# 7) Git for Windows (GitHub)
if (Has-App '^Git version' ([ref]$ver) -or Has-App '^Git$' ([ref]$ver)) {
  $addRows += New-SourceRow -Name 'Git for Windows' -Source github -Repo 'git-for-windows/git' -Strategy latest `
    -AssetRegex 'Git-.*-64-bit\.exe' -FileNameTemplate '{{asset}}' `
    -Type 'exe' -SilentArgs '/VERYSILENT /NORESTART' `
    -DetectType 'file' -DetectValue 'C:\Program Files\Git\bin\git.exe' -AddToPath 'C:\Program Files\Git\bin'
}

# 8) GitHub CLI (GitHub)
if (Has-App '^GitHub CLI' ([ref]$ver)) {
  $addRows += New-SourceRow -Name 'GitHub CLI' -Source github -Repo 'cli/cli' -Strategy pinned -Version ($ver -replace '[^\d\.]') `
    -AssetRegex 'gh_{{version}}_windows_amd64\.msi' -FileNameTemplate 'gh_{{version}}_windows_amd64.msi' `
    -Type 'msi' -SilentArgs '/qn /norestart' `
    -DetectType 'file' -DetectValue 'C:\Program Files\GitHub CLI\gh.exe'
}

# 9) PowerShell 7 (GitHub)
if (Has-App '^PowerShell 7' ([ref]$ver)) {
  $verTrim = ($ver -replace '[^\d\.]').Trim()
  $addRows += New-SourceRow -Name 'PowerShell 7-x64' -Source github -Repo 'PowerShell/PowerShell' -Strategy latest `
    -AssetRegex 'PowerShell-.*-win-x64\.msi' -FileNameTemplate '{{asset}}' `
    -Type 'msi' -SilentArgs '/qn /norestart' `
    -DetectType 'file' -DetectValue 'C:\Program Files\PowerShell\7\pwsh.exe'
}

# De-duplicate by Name against existing CSV
$namesExisting = @{}
foreach($e in $existing){ $namesExisting[$e.Name] = $true }
$finalAdds = $addRows | Where-Object { -not $namesExisting.ContainsKey($_.Name) }

if (-not $finalAdds -or $finalAdds.Count -eq 0) {
  Write-Host "No new rows to add. sources.csv already covers detected apps." -ForegroundColor Yellow
} else {
  Write-Host "Adding $($finalAdds.Count) row(s) to sources.csv:" -ForegroundColor Green
  $finalAdds | Select Name,Source,Repo,Strategy,Version,UrlTemplate,AssetRegex | Format-Table -Auto

  if ($WhatIf) {
    Write-Host "(WhatIf) Not writing changes." -ForegroundColor Yellow
  } else {
    # Merge & save, keeping existing rows first
    $out = @()
    $out += $existing
    $out += $finalAdds
    $out | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath
    Write-Host "sources.csv updated: $csvPath" -ForegroundColor Green
  }
}

if ($Rebuild -and -not $WhatIf) {
  Rebuild-FetchMap -RepoRoot $RepoRoot
  Write-Host "fetch-map.csv rebuilt." -ForegroundColor Green
} elseif ($Rebuild -and $WhatIf) {
  Write-Host "(WhatIf) Would have rebuilt fetch-map.csv." -ForegroundColor Yellow
}
