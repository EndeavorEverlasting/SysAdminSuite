<# ========================== GoLiveTools.ps1 ==========================
Utility cmdlets for go-live:
- Resolve-RepoRoot        : pick a working repo path (UNC or local)
- Preflight-Repo          : warn on missing files, create folders
- Assert-Repo             : enforce repo layout & write access
- Test-FetchMap           : validate fetch-map.csv rows/URLs (HEAD/GET)
- Rebuild-FetchMap        : build fetch-map.csv from sources.csv (robust tags)
- New-SourcesTemplate     : create a starter sources.csv if missing
- Invoke-Fetch            : wrapper for Fetch-Installers.ps1 (+ dry-run)
- New-RepoChecksums       : compute SHA256 for installers
- Guess-InstallerType     : MSI/NSIS/Inno/Squirrel/InstallShield/MSIX/ZIP
- Fill-PackagesTypes      : fill Type/SilentArgs in packages.csv
- Copy-SoftwareToClients  : robocopy repo to client PCs
- Get-ImpactS             : find ImpactS installs + shortcuts
- Fix-ImpactSShortcuts    : retarget bad shortcuts
- Quick-ExportManifest    : run your exporter
Requires: PowerShell 7+
====================================================================== #>

# ---- repo resolver: picks the first reachable path ----
param(
  [string]$RepoHost = $env:REPO_HOST,         # set env or pass -RepoHost PC123
  [string]$ShareName = 'SoftwareRepo',        # normal share name (preferred)
  [string]$LocalFallback = 'C:\SoftwareRepo'  # local fallback if present
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
  param(
    [string]$RepoServer,   # avoid collision with built-in $Host
    [string]$Share,
    [string]$Local
  )
  $candidates = @()
  if ($RepoServer) {
    $candidates += "\\$RepoServer\$Share"      # normal share
    $candidates += "\\$RepoServer\C`$\$Share"  # admin share fallback
  }
  if ($Local -and (Test-Path $Local)) { $candidates += $Local }
  foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
  if ($candidates.Count -gt 0) { return $candidates[0] }  # let later code create it
  throw "No repo candidates - pass -RepoHost HOSTNAME or create $Local"
}

$RepoRoot = Resolve-RepoRoot -RepoServer $RepoHost -Share $ShareName -Local $LocalFallback
Write-Host "Using RepoRoot: $RepoRoot" -ForegroundColor Green

function Import-SourcesYaml {
  <#
  .SYNOPSIS
    Parse Config/sources.yaml (or a path you supply) into a collection of
    PSCustomObjects with the same property names as the old sources.csv headers.
    Requires python3 on PATH for robust YAML parsing.
  .PARAMETER Path
    Path to sources.yaml. Defaults to sources.yaml next to GoLiveTools.ps1.
  .NOTES
    Parser limitation: the bundled regex-based fallback (used when python3 is
    unavailable) only handles flat key: value YAML scalars on a single line.
    Block/multi-line scalars (| or > style) in fields such as post_install will
    not parse correctly without python3. Keep all sources.yaml field values on
    a single line to ensure compatibility with both parsers.
  #>
  [CmdletBinding()]
  param(
    [string]$Path = (Join-Path $PSScriptRoot 'sources.yaml')
  )

  if (-not (Test-Path $Path)) {
    throw "sources.yaml not found: $Path  (run New-SourcesTemplate to create it)"
  }

  $py3 = (Get-Command python3 -ErrorAction SilentlyContinue) ?? (Get-Command python -ErrorAction SilentlyContinue)
  if ($py3) {
    # Use python3 for robust YAML parsing (no external modules required — pure stdlib)
    $pyScript = @'
import sys, json

def parse_yaml(path):
    with open(path, encoding='utf-8-sig') as f:
        lines = f.readlines()
    apps = []; i = 0; n = len(lines)

    def strip_comment(s):
        result = []; in_sq = False
        for ch in s:
            if ch == "'" and not in_sq: in_sq = True; result.append(ch); continue
            if ch == "'" and in_sq: in_sq = False; result.append(ch); continue
            if ch == '#' and not in_sq: break
            result.append(ch)
        return ''.join(result).rstrip()

    def unquote(s):
        s = s.strip()
        if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
            return s[1:-1]
        return s

    def indent_of(line): return len(line) - len(line.lstrip())

    while i < n:
        raw = lines[i]; line = strip_comment(raw).rstrip(); stripped = line.lstrip()
        if not stripped or stripped.startswith('#'): i += 1; continue
        ind = indent_of(raw)
        if ind == 0 and ':' in stripped:
            key = stripped.split(':', 1)[0].strip()
            if key == 'apps':
                i += 1
                while i < n:
                    raw2 = lines[i]; line2 = strip_comment(raw2).rstrip(); stripped2 = line2.lstrip()
                    if not stripped2 or stripped2.startswith('#'): i += 1; continue
                    ind2 = indent_of(raw2)
                    if ind2 == 0 and not stripped2.startswith('-'): break
                    if stripped2.startswith('- ') and ind2 == 2:
                        app = {}
                        rest = stripped2[2:].strip()
                        if ':' in rest:
                            k2, v2 = rest.split(':', 1); app[k2.strip()] = unquote(v2.strip())
                        i += 1
                        while i < n:
                            raw3 = lines[i]; line3 = strip_comment(raw3).rstrip(); stripped3 = line3.lstrip()
                            if not stripped3 or stripped3.startswith('#'): i += 1; continue
                            ind3 = indent_of(raw3)
                            if ind3 <= 2 and ind3 != 4: break
                            if ':' in stripped3:
                                k3, v3 = stripped3.split(':', 1); app[k3.strip()] = unquote(v3.strip())
                            i += 1
                        apps.append(app)
                    else: i += 1
                continue
        i += 1
    return apps

apps = parse_yaml(sys.argv[1])

# Remap YAML keys to the CSV column names expected by downstream functions
def remap(a):
    return {
        'Name':             a.get('name',''),
        'Source':           a.get('source',''),
        'Repo':             a.get('repo',''),
        'Strategy':         a.get('strategy',''),
        'Version':          a.get('version',''),
        'UrlTemplate':      a.get('url_template',''),
        'AssetRegex':       a.get('asset_regex',''),
        'FileNameTemplate': a.get('filename_template',''),
        'Type':             a.get('type',''),
        'SilentArgs':       a.get('silent_args',''),
        'DetectType':       a.get('detect_type',''),
        'DetectValue':      a.get('detect_value',''),
        'AddToPath':        a.get('add_to_path',''),
        'PostInstall':      a.get('post_install',''),
        'AllowDomains':     a.get('allow_domains',''),
        'Unmanaged':        str(a.get('unmanaged', '')).lower(),
    }

print(json.dumps([remap(a) for a in apps]))
'@
    $jsonOut = & $py3.Source "-c" $pyScript $Path 2>&1
    if ($LASTEXITCODE -ne 0) { throw "python3 YAML parse failed: $jsonOut" }
    $parsed = $jsonOut | ConvertFrom-Json
    return $parsed | ForEach-Object {
      [pscustomobject]@{
        Name             = $_.Name
        Source           = $_.Source
        Repo             = $_.Repo
        Strategy         = $_.Strategy
        Version          = $_.Version
        UrlTemplate      = $_.UrlTemplate
        AssetRegex       = $_.AssetRegex
        FileNameTemplate = $_.FileNameTemplate
        Type             = $_.Type
        SilentArgs       = $_.SilentArgs
        DetectType       = $_.DetectType
        DetectValue      = $_.DetectValue
        AddToPath        = $_.AddToPath
        PostInstall      = $_.PostInstall
        AllowDomains     = $_.AllowDomains
        Unmanaged        = $_.Unmanaged
      }
    }
  }

  # Fallback: lightweight line-by-line parser (no python3 available)
  # Handles the flat-mapping structure of sources.yaml
  Write-Warning "python3 not found — using built-in YAML parser (adequate for sources.yaml flat structure)"
  $lines = Get-Content $Path -Encoding UTF8
  $apps = [System.Collections.Generic.List[hashtable]]::new()
  $current = $null
  $inApps = $false

  foreach ($raw in $lines) {
    $line = ($raw -replace '#[^'']*$', '').TrimEnd()
    $stripped = $line.TrimStart()
    if ([string]::IsNullOrWhiteSpace($stripped)) { continue }
    $indent = $raw.Length - $raw.TrimStart().Length

    if ($indent -eq 0 -and $stripped -match '^apps:') { $inApps = $true; continue }
    if ($indent -eq 0 -and $stripped -notmatch '^-') { $inApps = $false; continue }

    if ($inApps) {
      if ($indent -eq 2 -and $stripped.StartsWith('- ')) {
        if ($current) { $apps.Add($current) }
        $current = @{ Name=''; Source=''; Repo=''; Strategy=''; Version=''; UrlTemplate=''; AssetRegex=''; FileNameTemplate=''; Type=''; SilentArgs=''; DetectType=''; DetectValue=''; AddToPath=''; PostInstall=''; AllowDomains=''; Unmanaged='' }
        $rest = $stripped.Substring(2)
        if ($rest -match '^(\w+):\s*(.*)$') { $k = $Matches[1]; $v = $Matches[2].Trim('"').Trim("'"); $current[$k] = $v }
      } elseif ($indent -eq 4 -and $current -and $stripped -match '^([\w_]+):\s*(.*)$') {
        $k = $Matches[1]; $v = $Matches[2].Trim('"').Trim("'"); $current[$k] = $v
      }
    }
  }
  if ($current) { $apps.Add($current) }

  return $apps | ForEach-Object {
    $a = $_
    [pscustomobject]@{
      Name             = $a.name ?? $a.Name ?? ''
      Source           = $a.source ?? $a.Source ?? ''
      Repo             = $a.repo ?? $a.Repo ?? ''
      Strategy         = $a.strategy ?? $a.Strategy ?? ''
      Version          = $a.version ?? $a.Version ?? ''
      UrlTemplate      = $a.url_template ?? $a.UrlTemplate ?? ''
      AssetRegex       = $a.asset_regex ?? $a.AssetRegex ?? ''
      FileNameTemplate = $a.filename_template ?? $a.FileNameTemplate ?? ''
      Type             = $a.type ?? $a.Type ?? ''
      SilentArgs       = $a.silent_args ?? $a.SilentArgs ?? ''
      DetectType       = $a.detect_type ?? $a.DetectType ?? ''
      DetectValue      = $a.detect_value ?? $a.DetectValue ?? ''
      AddToPath        = $a.add_to_path ?? $a.AddToPath ?? ''
      PostInstall      = $a.post_install ?? $a.PostInstall ?? ''
      AllowDomains     = $a.allow_domains ?? $a.AllowDomains ?? ''
      Unmanaged        = $a.unmanaged ?? $a.Unmanaged ?? ''
    }
  }
}

function Preflight-Repo {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $installers  = Join-Path $RepoRoot 'installers'
  $checksums   = Join-Path $RepoRoot 'checksums'
  $pkgCsv      = Join-Path $RepoRoot 'packages.csv'
  $fetchMap    = Join-Path $RepoRoot 'fetch-map.csv'
  $sourcesYaml = Join-Path $RepoRoot 'sources.yaml'
  $sourcesCsv  = Join-Path $RepoRoot 'sources.csv'  # legacy

  foreach($d in @($installers,$checksums)){
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  }

  $warns = @()
  if (-not (Test-Path $sourcesYaml)) {
    if (Test-Path $sourcesCsv) {
      $warns += "sources.csv found but sources.yaml missing. Run: & '$PSScriptRoot\Config\sources.csv' migration or New-SourcesTemplate."
    } else {
      $warns += "Missing sources.yaml -> $sourcesYaml (run: New-SourcesTemplate -RepoRoot `"$RepoRoot`")"
    }
  }
  if (-not (Test-Path $fetchMap))   { $warns += "Missing fetch-map.csv -> $fetchMap (run: Rebuild-FetchMap -RepoRoot `"$RepoRoot`")" }
  if (-not (Test-Path $pkgCsv))     { $warns += "Missing packages.csv -> $pkgCsv (will be created by Fetch-Installers merge)" }

  if ($warns.Count) {
    Write-Warning ("Preflight warnings:`n - " + ($warns -join "`n - "))
  } else {
    Write-Host "Preflight OK at $RepoRoot" -ForegroundColor Green
  }
}

function Assert-Repo {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $paths = [ordered]@{
    RepoRoot    = $RepoRoot
    Installers  = Join-Path $RepoRoot 'installers'
    Checksums   = Join-Path $RepoRoot 'checksums'
    PkgCsv      = Join-Path $RepoRoot 'packages.csv'
    FetchMap    = Join-Path $RepoRoot 'fetch-map.csv'
    SourcesYaml = Join-Path $RepoRoot 'sources.yaml'
  }

  foreach($k in $paths.Keys){
    if ($k -in @('PkgCsv','FetchMap','SourcesYaml')) { continue } # files optional
    if (-not (Test-Path $paths[$k])) {
      if ($k -eq 'RepoRoot') { throw "Repo missing: $($paths[$k])" }
      New-Item -ItemType Directory -Force -Path $paths[$k] | Out-Null
    }
  }

  # write test
  $wtest = Join-Path $paths.Installers ".write-test"
  try { "ok" | Out-File $wtest -Encoding ascii ; Remove-Item $wtest -Force }
  catch { throw "No write access to installers: $($paths.Installers). Run elevated or fix share perms." }

  [pscustomobject]$paths
}

function Test-FetchMap {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [int]$TimeoutSec = 15,
    [switch]$HeadOnly
  )

  $fetch = Join-Path $RepoRoot 'fetch-map.csv'
  if (-not (Test-Path $fetch)) { throw "Missing fetch-map.csv at $fetch (Run Rebuild-FetchMap first.)" }
  $rows = Import-Csv $fetch | Where-Object { $_.Url -and $_.FileName -and $_.Type }
  if (-not $rows) { throw "fetch-map.csv has no valid rows." }

  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $ua = "SysAdminSuite-URLTest/1.0 (+PowerShell)"

  $results = foreach($r in $rows){
    $url = $r.Url
    $code = $null; $len = $null; $final = $null; $err = $null
    try{
      $req = [System.Net.WebRequest]::Create($url)
      $req.Method = $HeadOnly ? 'HEAD' : 'GET'
      $req.Timeout = $TimeoutSec * 1000
      $req.UserAgent = $ua
      $resp = $req.GetResponse()
      $code = [int]$resp.StatusCode
      $len  = $resp.ContentLength
      $final = $resp.ResponseUri.AbsoluteUri
      $resp.Close()
    } catch {
      $err = $_.Exception.Message
    }
    [pscustomobject]@{
      Name=$r.Name; Url=$url; FinalUrl=$final; Status=$code; Bytes=$len; Error=$err
    }
  }

  $bad = $results | Where-Object { $_.Error -or ($_.Status -lt 200 -or $_.Status -ge 400) }
  [pscustomobject]@{ Total=$results.Count; Bad=$bad.Count; Results=$results }
}

# Robust GitHub resolver for Build-FetchMap
function Resolve-GitHubRelease {
  param([Parameter(Mandatory)][string]$Repo, [ValidateSet('latest','pinned')][string]$Strategy, [string]$Version)
  $ua="SysAdminSuite-Resolve/1.1 (+PowerShell)"
  if ($Strategy -eq 'latest') {
    return Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent'=$ua }
  }
  $tagCandidates = @($Version, "v$Version", ($Version -replace '^v','')) | Select-Object -Unique
  foreach($t in $tagCandidates){
    try { return Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$t" -Headers @{ 'User-Agent'=$ua } } catch {}
  }
  $rels = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=100" -Headers @{ 'User-Agent'=$ua }
  $rx = "^v?$([Regex]::Escape(($Version -replace '^v','')))$"
  $hit = $rels | Where-Object { $_.tag_name -match $rx } | Select-Object -First 1
  if ($hit) { return $hit }
  throw "Pinned release not found for $Repo / version '$Version'."
}

function New-SourcesTemplate {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $path = Join-Path $RepoRoot 'sources.yaml'
  if (Test-Path $path) { Write-Host "sources.yaml already exists: $path" -ForegroundColor Yellow; return }
  @'
# SysAdmin Suite — sources.yaml starter template
# See Config/lib/sources-schema.yaml for full field documentation.

lists:
  workstation-baseline:
    - Google Chrome
    - Git for Windows
    - GitHub CLI

apps:
  - name: Google Chrome
    source: url
    repo: ""
    strategy: latest
    version: ""
    url_template: "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
    asset_regex: ""
    filename_template: ChromeEnterprise64.msi
    type: msi
    silent_args: "/qn /norestart"
    detect_type: regkey
    detect_value: 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome'
    add_to_path: ""
    post_install: ""
    allow_domains: ""

  - name: Git for Windows
    source: github
    repo: git-for-windows/git
    strategy: latest
    version: ""
    url_template: ""
    asset_regex: 'Git-.*-64-bit\.exe'
    filename_template: "{{asset}}"
    type: exe
    silent_args: "/VERYSILENT /NORESTART"
    detect_type: file
    detect_value: 'C:\Program Files\Git\bin\git.exe'
    add_to_path: 'C:\Program Files\Git\bin'
    post_install: ""
    allow_domains: ""

  - name: GitHub CLI
    source: github
    repo: cli/cli
    strategy: pinned
    version: "2.60.1"
    url_template: ""
    asset_regex: 'gh_{{version}}_windows_amd64\.msi'
    filename_template: "gh_{{version}}_windows_amd64.msi"
    type: msi
    silent_args: "/qn /norestart"
    detect_type: file
    detect_value: 'C:\Program Files\GitHub CLI\gh.exe'
    add_to_path: ""
    post_install: ""
    allow_domains: ""
'@ | Set-Content -Path $path -Encoding UTF8
  Write-Host "Created starter sources.yaml at: $path" -ForegroundColor Green
}

function Rebuild-FetchMap {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$SourcesYaml = (Join-Path $RepoRoot 'sources.yaml'),
    [string]$SourcesCsv  = (Join-Path $RepoRoot 'sources.csv'),  # legacy fallback
    [string[]]$AllowList = @("api.github.com","github.com","objects.githubusercontent.com","dl.google.com","download.visualstudio.microsoft.com","aka.ms","python.org","www.python.org","obsidian.md","githubusercontent.com"),
    [switch]$WhatIf
  )

  # Prefer sources.yaml; fall back to sources.csv with a warning
  if (Test-Path $SourcesYaml) {
    $src = Import-SourcesYaml -Path $SourcesYaml
    Write-Host "Reading from sources.yaml: $SourcesYaml" -ForegroundColor Cyan
  } elseif (Test-Path $SourcesCsv) {
    Write-Warning "sources.yaml not found — falling back to legacy sources.csv. Migrate with: cp sources.csv and update to YAML."
    $src = Import-Csv $SourcesCsv
  } else {
    throw "Neither sources.yaml ($SourcesYaml) nor sources.csv ($SourcesCsv) found. Run: New-SourcesTemplate -RepoRoot `"$RepoRoot`""
  }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  $rows = foreach($r in $src){
    $name=$r.Name; $url=$null; $file=$null
    $source = ($r.Source ?? 'url').ToLower()
    $strategy = ($r.Strategy ?? 'pinned').ToLower()

    switch ($source) {
      'github' {
        if (-not $r.Repo) { throw "Row '$name': Repo required for Source=github" }
        $rel    = Resolve-GitHubRelease -Repo $r.Repo -Strategy $strategy -Version $r.Version
        $tagVer = $rel.tag_name.TrimStart('v')
        # Substitute {{version}} in AssetRegex before matching (e.g. GitHub CLI, PowerShell pinned entries)
        $resolvedAssetRegex = $r.AssetRegex -replace '\{\{version\}\}', [Regex]::Escape($tagVer)
        $asset = $rel.assets | Where-Object { $_.name -match $resolvedAssetRegex } | Select-Object -First 1
        if (-not $asset) { throw "Row '$name': no asset matched '$resolvedAssetRegex' in $($r.Repo) [tag $($rel.tag_name)]" }
        $url  = $asset.browser_download_url
        $file = if ($r.FileNameTemplate -match '\{\{version\}\}') {
                  $r.FileNameTemplate -replace '\{\{version\}\}', $tagVer
                } elseif ($r.FileNameTemplate -and $r.FileNameTemplate -notmatch '\{\{asset\}\}') {
                  $r.FileNameTemplate
                } else {
                  $asset.name   # {{asset}} or empty -> use actual release asset filename
                }
      }
      'url' {
        $tmpl = $r.UrlTemplate; if (-not $tmpl -and $r.Url) { $tmpl = $r.Url }
        if (-not $tmpl) { throw "Row '$name': UrlTemplate (or Url) required for Source=url" }
        $url  = $tmpl -replace '\{\{version\}\}', $r.Version
        $file = ($r.FileNameTemplate) ? ($r.FileNameTemplate -replace '\{\{version\}\}', $r.Version) : (Split-Path $url -Leaf)
      }
      default { throw "Row '$name': Unknown Source '$source'" }
    }

    # allow-list
    $h = ([uri]$url).Host.ToLower()
    if (-not ($AllowList | Where-Object { $h -eq $_ -or $h.EndsWith(".$_") })) {
      throw "Row '$name': URL host not in allow-list -> $url"
    }

    [pscustomobject]@{
      Name=$name; Url=$url; FileName=$file;
      Type=$r.Type; SilentArgs=$r.SilentArgs; DetectType=$r.DetectType; DetectValue=$r.DetectValue;
      AddToPath=$r.AddToPath; PostInstall=$r.PostInstall; AllowDomains=$r.AllowDomains
    }
  }

  $outPath = Join-Path $RepoRoot 'fetch-map.csv'
  if ($WhatIf) { $rows | Format-Table Name,Url,FileName,Type -Auto; return }
  $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $outPath
  Write-Host "fetch-map.csv written: $outPath" -ForegroundColor Green
}

function Invoke-Fetch {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [switch]$DryRun,
    [int]$MaxParallel=4
  )
  $script = Join-Path $PSScriptRoot 'Fetch-Installers.ps1'
  if (-not (Test-Path $script)) { throw "Fetch-Installers.ps1 not found next to GoLiveTools.ps1" }
  $fetchArgs = @('-RepoRoot', $RepoRoot, '-MaxParallel', $MaxParallel)
  if ($DryRun) { $fetchArgs += '-DryRun' }
  # Prefer sources.yaml when present; Fetch-Installers.ps1 falls back to fetch-map.csv otherwise
  $yamlPath = Join-Path $PSScriptRoot 'sources.yaml'
  if (Test-Path $yamlPath) {
    $fetchArgs += @('-SourcesYaml', $yamlPath)
    Write-Host "Invoke-Fetch: using $yamlPath" -ForegroundColor Cyan
  }
  & $script @fetchArgs
}

function New-RepoChecksums {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $inst = Join-Path $RepoRoot 'installers'
  $chk  = Join-Path $RepoRoot 'checksums'
  New-Item -ItemType Directory -Force -Path $chk | Out-Null
  Get-ChildItem $inst -File | ForEach-Object{
    $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    $out = Join-Path $chk ($_.Name + '.sha256')
    $h | Out-File $out -Encoding ascii -NoNewline
  }
  Write-Host "Checksums refreshed in $chk" -ForegroundColor Green
}

function Guess-InstallerType {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)
  $ext = [IO.Path]::GetExtension($Path).ToLower()
  if ($ext -eq '.msi') { return 'msi' }
  if ($ext -eq '.msix' -or $ext -eq '.msixbundle' -or $ext -eq '.appx' -or $ext -eq '.appxbundle') { return 'msix' }
  if ($ext -eq '.zip') { return 'zip' }
  # fingerprint EXE
  $fs = [IO.File]::Open($Path,'Open','Read','ReadWrite')
  try{
    $buf = New-Object byte[] 8192
    [void]$fs.Read($buf,0,$buf.Length)
    $txt = [Text.Encoding]::ASCII.GetString($buf)
    if ($txt -match 'Inno Setup')         { return 'exe:inno' }
    if ($txt -match 'Nullsoft')           { return 'exe:nsis' }
    if ($txt -match 'Squirrel.Windows')   { return 'exe:squirrel' }
    if ($txt -match 'InstallShield')      { return 'exe:installshield' }
    return 'exe'
  } finally { $fs.Close() }
}

function Fill-PackagesTypes {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $pkg = Join-Path $RepoRoot 'packages.csv'
  if (-not (Test-Path $pkg)) { throw "packages.csv not found at $pkg" }
  $inst = Join-Path $RepoRoot 'installers'
  $rows = Import-Csv $pkg
  foreach($r in $rows){
    $file = Join-Path $inst $r.InstallerFile
    if (-not (Test-Path $file)) { continue }
    if (-not $r.Type -or $r.Type -eq '') {
      $kind = Guess-InstallerType -Path $file
      switch -Regex ($kind) {
        '^msi$'               { $r.Type='msi';  if (-not $r.SilentArgs) { $r.SilentArgs='/qn /norestart' } }
        '^exe:nsis$'          { $r.Type='exe';  if (-not $r.SilentArgs) { $r.SilentArgs='/S' } }
        '^exe:inno$'          { $r.Type='exe';  if (-not $r.SilentArgs) { $r.SilentArgs='/VERYSILENT /NORESTART' } }
        '^exe:squirrel$'      { $r.Type='exe';  if (-not $r.SilentArgs) { $r.SilentArgs='--silent' } }
        '^exe:installshield$' { $r.Type='exe';  if (-not $r.SilentArgs) { $r.SilentArgs='/s /v"/qn REBOOT=ReallySuppress"' } }
        '^exe$'               { $r.Type='exe';  if (-not $r.SilentArgs) { $r.SilentArgs='/S' } }
        '^zip$'               { $r.Type='zip' }
        '^msix$'              { $r.Type='msix' }
      }
    }
  }
  $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $pkg
  Write-Host "packages.csv updated with Type/SilentArgs where missing." -ForegroundColor Green
}

function Copy-SoftwareToClients {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string[]]$ComputerName,
    [string]$TargetPath = "C$\SoftwareRepo",
    [int]$MaxParallel = 6
  )
  $src = $RepoRoot.TrimEnd('\')
  $jobs = foreach ($comp in $ComputerName) {
    $dst = "\\$comp\$TargetPath"
    Start-ThreadJob -ScriptBlock {
      param($comp,$src,$dst)
      if (-not (Test-Path "\\$comp\C$")) { throw "Host unreachable: $comp" }
      $robocopyArgs = @($src, $dst, '/MIR','/Z','/W:2','/R:2','/NFL','/NDL','/NP','/XO','/FFT')
      $rc = Start-Process -FilePath 'robocopy.exe' -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
      [pscustomobject]@{ Computer=$comp; ExitCode=$rc.ExitCode; Dest=$dst }
    } -ArgumentList $comp,$src,$dst
  }
  Receive-Job -Job $jobs -Wait -AutoRemoveJob
}

function Get-ImpactS {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string[]]$ComputerName,
    [int]$ThrottleLimit=16
  )
  $script = {
    $names = @('ImpactS','Impact S','ImpactS Client','ImpactS Desktop')
    $paths = @(
      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $hits = @()
    foreach($p in $paths){
      Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object {
        $x = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
        if ($x.DisplayName) {
          foreach($n in $names){
            if ($x.DisplayName -like "*$n*"){
              $hits += [pscustomobject]@{
                DisplayName=$x.DisplayName; Version=$x.DisplayVersion; Uninstall=$x.UninstallString; RegPath=$_.PsPath
              }
            }
          }
        }
      }
    }
    # Shortcut scan
    $roots = @("$Env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$Env:Public\Desktop")
    $lnkHits = @()
    try{
      $W = New-Object -ComObject WScript.Shell
      foreach($root in $roots){
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
          $sh = $W.CreateShortcut($_.FullName)
          if ($sh.TargetPath -and ($sh.TargetPath -match 'ImpactS' -or $sh.Description -match 'ImpactS')){
            $lnkHits += [pscustomobject]@{ Shortcut=$_.FullName; Target=$sh.TargetPath }
          }
        }
      }
    } catch {
      Write-Error ("ImpactS shortcut scan failed. Roots: {0}. Error: {1}" -f ($roots -join '; '), $_.Exception.Message)
    }
    [pscustomobject]@{ ARP=$hits; Shortcuts=$lnkHits }
  }

  Invoke-Command -ComputerName $ComputerName -ScriptBlock $script -ThrottleLimit $ThrottleLimit |
    Select-Object @{n='ComputerName';e={$_.PSComputerName}}, ARP, Shortcuts
}

function Fix-ImpactSShortcuts {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string[]]$ComputerName,
    [Parameter(Mandatory)][string]$OldDir,   # e.g. "C:\Program Files\ImpactS\bin"
    [Parameter(Mandatory)][string]$NewDir,   # e.g. "C:\Program Files\ImpactS\Client"
    [switch]$WhatIf
  )
  $script = {
    param($OldDir,$NewDir,$WhatIf)
    $roots = @("$Env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$Env:Public\Desktop")
    $edited = @()
    try{
      $W = New-Object -ComObject WScript.Shell
      foreach($root in $roots){
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
          try {
            $lnk = $W.CreateShortcut($_.FullName)
            if ($lnk.TargetPath -and $lnk.TargetPath -like "$OldDir*") {
              $old = $lnk.TargetPath
              $newTarget = ($old -replace [Regex]::Escape($OldDir), $NewDir)
              if (-not $WhatIf) { $lnk.TargetPath = $newTarget; $lnk.Save() }
              $edited += [pscustomobject]@{ Shortcut=$_.FullName; Old=$old; New=$newTarget }
            }
          } catch {
            $edited += [pscustomobject]@{
              Shortcut = $_.FullName
              Error    = $_.Exception.Message
              Root     = $root
              OldTarget= $OldDir
            }
          }
        }
      }
    } catch {
      $edited += [pscustomobject]@{
        Shortcut = $null
        Error    = $_.Exception.Message
        Root     = ($roots -join '; ')
        OldTarget= $OldDir
      }
    }
    $edited
  }
  Invoke-Command -ComputerName $ComputerName -ScriptBlock $script -ArgumentList $OldDir,$NewDir,$WhatIf |
    Select-Object @{n='ComputerName';e={$_.PSComputerName}}, Shortcut, Old, New
}

function Quick-ExportManifest {
  [CmdletBinding()]
  param([string]$Exporter = (Join-Path $PSScriptRoot 'Export-Software_Manifest.ps1'))
  if (-not (Test-Path $Exporter)) { throw "Exporter not found: $Exporter" }
  & $Exporter
}