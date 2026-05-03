<#
Fetch-Installers.ps1 - vendor-only fetcher with backbone.
Reads sources.yaml (preferred) or fetch-map.csv -> resolves GitHub release URLs ->
downloads installers -> writes checksums -> updates packages.csv.
No winget. Parallel, retried, verified, and loud.

Primary workflow (YAML-first, no fetch-map.csv required):
  .\Fetch-Installers.ps1 -RepoRoot C:\SoftwareRepo -SourcesYaml .\sources.yaml

Legacy workflow (fetch-map.csv):
  .\Fetch-Installers.ps1 -RepoRoot \\SERVER\SoftwareRepo -FetchMap .\fetch-map.csv

Notes:
- When -SourcesYaml is used, GitHub release URLs are resolved in real-time (latest/pinned).
- When -FetchMap is used, URLs must already be resolved in the CSV (produced by Rebuild-FetchMap).
- AllowDomains (optional) is semicolon-separated and augments -AllowList.
- Run this on a box with internet; target RepoRoot may be local path or UNC.

Examples:
  .\Fetch-Installers.ps1 -RepoRoot C:\SoftwareRepo -SourcesYaml .\Config\sources.yaml
  .\Fetch-Installers.ps1 -RepoRoot \\SERVER\SoftwareRepo -SourcesYaml .\Config\sources.yaml -Only "Google Chrome"
  .\Fetch-Installers.ps1 -RepoRoot \\SERVER\SoftwareRepo -FetchMap .\fetch-map.csv -DryRun
  .\Fetch-Installers.ps1 -RepoRoot C:\SoftwareRepo -MaxParallel 4
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$RepoRoot,                           # e.g. C:\SoftwareRepo OR \\HOST\SoftwareRepo
  [string]$SourcesYaml = "",                   # preferred: path to sources.yaml
  [string]$FetchMap = ".\fetch-map.csv",       # legacy: pre-resolved fetch-map.csv
  [string[]]$Only,                              # limit by Name
  [int]$MaxParallel = 4,
  [int]$MaxRetries  = 4,
  [int]$MinBytes    = 50*1024,                  # sanity floor
  [switch]$DryRun,
  [string[]]$AllowList = @(
    "github.com","objects.githubusercontent.com","api.github.com",
    "dl.google.com","go.microsoft.com","download.visualstudio.microsoft.com","aka.ms",
    "python.org","www.python.org","obsidian.md","githubusercontent.com"
  ),
  [switch]$SkipSignatureCheck
)

$ErrorActionPreference = 'Stop'

function Fail($m){ Write-Error $m; exit 2 }
function Info($m){ Write-Host $m -ForegroundColor Cyan }
function Good($m){ Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }

# --- Repo layout checks ------------------------------------------------------
if (-not (Test-Path $RepoRoot)) { Fail "RepoRoot not found: $RepoRoot" }
$Installers = Join-Path $RepoRoot 'installers'
$Checksums  = Join-Path $RepoRoot 'checksums'
$PkgCsv     = Join-Path $RepoRoot 'packages.csv'
New-Item -ItemType Directory -Force -Path $Installers,$Checksums | Out-Null

# write-test
$testFile = Join-Path $Installers ".write-test"
try { "ok" | Out-File $testFile -Encoding ascii ; Remove-Item $testFile -Force } catch { Fail "No write access to $Installers - fix perms or run elevated." }

# --- Inline YAML parser (no external modules) --------------------------------
function Import-SourcesYamlInline {
  param([string]$Path)
  if (-not (Test-Path $Path)) { throw "sources.yaml not found: $Path" }
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

def remap(a):
    return {
        'Name':             a.get('name',''),
        'Source':           a.get('source','url'),
        'Repo':             a.get('repo',''),
        'Strategy':         a.get('strategy','pinned'),
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

print(json.dumps([remap(a) for a in parse_yaml(sys.argv[1])]))
'@
  $py3 = (Get-Command python3 -ErrorAction SilentlyContinue) ?? (Get-Command python -ErrorAction SilentlyContinue)
  if (-not $py3) { throw "python3 is required to parse sources.yaml. Add it to PATH or supply -FetchMap instead." }
  $out = & $py3.Source "-c" $pyScript $Path 2>&1
  if ($LASTEXITCODE -ne 0) { throw "YAML parse failed: $out" }
  $parsed = $out | ConvertFrom-Json
  return $parsed | ForEach-Object {
    [pscustomobject]@{
      Name=($_.Name); Source=($_.Source); Repo=($_.Repo); Strategy=($_.Strategy)
      Version=($_.Version); UrlTemplate=($_.UrlTemplate); AssetRegex=($_.AssetRegex)
      FileNameTemplate=($_.FileNameTemplate); Type=($_.Type); SilentArgs=($_.SilentArgs)
      DetectType=($_.DetectType); DetectValue=($_.DetectValue); AddToPath=($_.AddToPath)
      PostInstall=($_.PostInstall); AllowDomains=($_.AllowDomains); Unmanaged=($_.Unmanaged)
    }
  }
}

function Resolve-ReleaseUrl {
  param(
    [string]$Name,
    [string]$Source,
    [string]$Repo,
    [string]$Strategy,
    [string]$Version,
    [string]$UrlTemplate,
    [string]$AssetRegex,
    [string]$FileNameTemplate,
    [string[]]$GlobalAllowList
  )
  $ua = "SysAdminSuite-Fetch/1.1 (+PowerShell)"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $url = $null; $file = $null

  switch ($Source.ToLower()) {
    'github' {
      if (-not $Repo) { throw "'$Name': Repo is required for Source=github" }
      $strategy = ($Strategy ?? 'latest').ToLower()
      $rel = if ($strategy -eq 'latest') {
        Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent'=$ua }
      } else {
        $candidates = @($Version, "v$Version", ($Version -replace '^v','')) | Select-Object -Unique
        $hit = $null
        foreach($t in $candidates){
          try { $hit = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$t" -Headers @{ 'User-Agent'=$ua }; break } catch {}
        }
        if (-not $hit) {
          $rels = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=100" -Headers @{ 'User-Agent'=$ua }
          $rx = "^v?$([Regex]::Escape(($Version -replace '^v','')))`$"
          $hit = $rels | Where-Object { $_.tag_name -match $rx } | Select-Object -First 1
        }
        if (-not $hit) { throw "'$Name': Pinned release '$Version' not found in $Repo" }
        $hit
      }
      $tagVer = $rel.tag_name.TrimStart('v')
      # Substitute {{version}} in AssetRegex before matching (pinned entries like GitHub CLI, PowerShell)
      $resolvedAssetRegex = $AssetRegex -replace '\{\{version\}\}', [Regex]::Escape($tagVer)
      $asset = $rel.assets | Where-Object { $_.name -match $resolvedAssetRegex } | Select-Object -First 1
      if (-not $asset) { throw "'$Name': No asset matched '$resolvedAssetRegex' in $Repo [tag $($rel.tag_name)]" }
      $url = $asset.browser_download_url
      $file = if ($FileNameTemplate -match '\{\{version\}\}') { $FileNameTemplate -replace '\{\{version\}\}', $tagVer }
              elseif ($FileNameTemplate -and $FileNameTemplate -notmatch '\{\{asset\}\}') { $FileNameTemplate }
              else { $asset.name }
    }
    'url' {
      $tmpl = if ($UrlTemplate) { $UrlTemplate } else { throw "'$Name': UrlTemplate required for Source=url" }
      $url  = $tmpl -replace '\{\{version\}\}', $Version
      $file = if ($FileNameTemplate) { $FileNameTemplate -replace '\{\{version\}\}', $Version } else { Split-Path $url -Leaf }
    }
    default { throw "'$Name': Unknown Source '$Source'" }
  }

  # allow-list check
  $h = ([uri]$url).Host.ToLower()
  if (-not ($GlobalAllowList | Where-Object { $h -eq $_ -or $h.EndsWith(".$_") })) {
    throw "'$Name': URL host not in allow-list -> $url"
  }

  [pscustomobject]@{ Url=$url; FileName=$file }
}

# --- Load plan --------------------------------------------------------------
$rows = $null

if ($SourcesYaml -and ($SourcesYaml -ne "")) {
  # YAML-first path: parse sources.yaml and resolve URLs in real-time
  if (-not (Test-Path $SourcesYaml)) { Fail "sources.yaml not found: $SourcesYaml" }
  Info "Reading from sources.yaml: $SourcesYaml"
  $src = Import-SourcesYamlInline -Path $SourcesYaml
  if ($Only) { $src = $src | Where-Object { $Only -contains $_.Name } }
  $src = $src | Where-Object { -not ($_.Unmanaged -eq 'true') }
  if (-not $src -or $src.Count -eq 0) { Fail "Nothing to do. Check your filters or sources.yaml content." }

  $rows = foreach ($r in $src) {
    $resolved = Resolve-ReleaseUrl `
      -Name $r.Name -Source $r.Source -Repo $r.Repo -Strategy $r.Strategy `
      -Version $r.Version -UrlTemplate $r.UrlTemplate -AssetRegex $r.AssetRegex `
      -FileNameTemplate $r.FileNameTemplate -GlobalAllowList $AllowList
    [pscustomobject]@{
      Name=$r.Name; Url=$resolved.Url; FileName=$resolved.FileName
      Type=$r.Type; SilentArgs=$r.SilentArgs; DetectType=$r.DetectType
      DetectValue=$r.DetectValue; AddToPath=$r.AddToPath; PostInstall=$r.PostInstall
      AllowDomains=$r.AllowDomains
    }
  }
} else {
  # Legacy path: read pre-resolved fetch-map.csv
  if (-not (Test-Path $FetchMap)) { Fail "Missing fetch-map: $FetchMap  (tip: supply -SourcesYaml to skip this step)" }
  Info "Reading from fetch-map.csv: $FetchMap"
  $rows = Import-Csv $FetchMap
  if ($Only) { $rows = $rows | Where-Object { $Only -contains $_.Name } }
  $rows = $rows | Where-Object { $_.Url -and $_.FileName -and $_.Type }
}

if (-not $rows -or $rows.Count -eq 0) { Fail "Nothing to do. Check your filters or source file content." }
# Validate allow-list for CSV path (YAML path validates inline during URL resolution)
if (-not $SourcesYaml) {
  foreach ($r in $rows) {
    try { $h = ([uri]$r.Url).Host.ToLower() } catch { Fail "Bad URL for $($r.Name): $($r.Url)" }
    $ok = $false
    $extra = @(); if ($r.AllowDomains) { $extra = $r.AllowDomains -split ';' }
    foreach($d in ($extra + $AllowList)) { if ($d -and ($h -eq $d.ToLower() -or $h.EndsWith(".$($d.ToLower())"))) { $ok = $true; break } }
    if (-not $ok) { Fail "Blocked by allow-list: $h  (URL: $($r.Url))" }
  }
}

# --- Helpers ----------------------------------------------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UA = "SysAdminSuite-Fetch/1.1 (+PowerShell)"

function Check-AllowList([string]$url, [string[]]$rowAllow){
  try {
    $uriHost = ([uri]$url).Host.ToLower()
  } catch { Fail "Bad URL: $url" }
  $ok = $false
  foreach($dom in ($rowAllow + $AllowList)){
    if ($null -eq $dom -or $dom -eq "") { continue }
    $d = $dom.ToLower()
    if ($uriHost -eq $d -or $uriHost.EndsWith(".$d")) { $ok = $true; break }
  }
  if (-not $ok) { Fail "Blocked by allow-list: $uriHost  (URL: $url)" }
}

# Build job list
$jobs = foreach($r in $rows){
  $allow = @()
  if ($r.AllowDomains) { $allow = $r.AllowDomains -split ';' }
  Check-AllowList $r.Url $allow

  [pscustomobject]@{
    Name        = $r.Name
    Url         = $r.Url
    Dest        = (Join-Path $Installers $r.FileName)
    Type        = $r.Type
    SilentArgs  = $r.SilentArgs
    DetectType  = $r.DetectType
    DetectValue = $r.DetectValue
    AddToPath   = $r.AddToPath
    PostInstall = $r.PostInstall
  }
}

# --- Dry-run ---------------------------------------------------------------
if ($DryRun){
  Info "DRY-RUN: would fetch $($jobs.Count) file(s) into $Installers"
  $jobs | ForEach-Object { "{0} <= {1}" -f $_.Dest, $_.Url }
  return
}

# --- Parallel fetch (PowerShell 7+) ----------------------------------------
$throttle = [Math]::Max(1,[Math]::Min($MaxParallel,16))

$results =
  $jobs |
  ForEach-Object -Parallel {
    $out = [pscustomobject]@{
      Name       = $_.Name
      File       = $_.Dest
      Url        = $_.Url
      Ok         = $false
      Hash       = $null
      Sig        = $null
      SigSubject = $null
      Error      = $null
    }

    try {
      $destDir = [System.IO.Path]::GetDirectoryName($_.Dest)
      if (!(Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }

      # atomic download with retries
      $tmp = "$($_.Dest).part"
      for($i=1; $i -le $using:MaxRetries; $i++){
        $wc = $null
        try{
          if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
          $wc = New-Object System.Net.WebClient
          $wc.Headers['User-Agent'] = $using:UA
          $wc.DownloadFile($_.Url, $tmp)

          $len = (Get-Item $tmp).Length
          if ($len -lt $using:MinBytes) { throw "size $len < $($using:MinBytes)" }

          Move-Item $tmp $_.Dest -Force
          break
        } catch {
          if ($i -eq $using:MaxRetries) { throw }
          Start-Sleep -Seconds ([math]::Min(30, [math]::Pow(2,$i)))
        } finally {
          if ($wc) { $wc.Dispose() }
        }
      }

      # checksum
      $hash = (Get-FileHash -Algorithm SHA256 -Path $_.Dest).Hash
      $chk  = Join-Path $using:Checksums ((Split-Path $_.Dest -Leaf) + ".sha256")
      $hash | Out-File $chk -Encoding ascii -NoNewline

      # signature (best-effort)
      try{
        $sig = Get-AuthenticodeSignature -FilePath $_.Dest
        $out.Sig = $sig.Status.ToString()
        $out.SigSubject = $sig.SignerCertificate.Subject
      } catch { $out.Sig = 'Unknown' }

      $out.Hash = $hash
      $out.Ok = $true
    }
    catch {
      $out.Error = $_.Exception.Message
    }

    $out  # return the result object
  } -ThrottleLimit $throttle

# --- Report fetch outcome ----------------------------------------------------
$ok  = $results | Where-Object { $_.Ok }
$bad = $results | Where-Object { -not $_.Ok }
$warnUnsigned = $ok | Where-Object { $_.Sig -ne 'Valid' -and $_.Sig -ne $null }

Good  "Fetched: $($ok.Count) / $($results.Count)"
if ($warnUnsigned.Count -gt 0 -and -not $SkipSignatureCheck){
  Warn ("Unsigned or non-valid signatures ({0}):" -f $warnUnsigned.Count)
  $warnUnsigned | ForEach-Object { Write-Host (" - {0} [{1}]" -f $_.File, $_.Sig) -ForegroundColor Yellow }
}
if ($bad.Count -gt 0){
  Write-Host "Failures ($($bad.Count)):" -ForegroundColor Red
  $bad | ForEach-Object { Write-Host (" - {0} <= {1}  :: {2}" -f $_.File, $_.Url, $_.Error) -ForegroundColor Red }
  Fail "One or more downloads failed."
}

# --- Merge into packages.csv -------------------------------------------------
function Merge-Packages($PkgCsv, $jobs){
  $newRows = foreach($j in $jobs){
    [pscustomobject]@{
      Name         = $j.Name
      InstallerFile= (Split-Path $j.Dest -Leaf)
      Type         = $j.Type
      SilentArgs   = $j.SilentArgs
      DetectType   = $j.DetectType
      DetectValue  = $j.DetectValue
      PostInstall  = $j.PostInstall
      AddToPath    = $j.AddToPath
    }
  }

  if (Test-Path $PkgCsv){
    $existing = Import-Csv $PkgCsv
    $index = @{}
    foreach($e in $existing){ $index[$e.Name] = $e }

    foreach($nr in $newRows){
      if ($index.ContainsKey($nr.Name)){
        $e = $index[$nr.Name]
        foreach($col in 'InstallerFile','Type','SilentArgs','DetectType','DetectValue','PostInstall','AddToPath'){
          if ($nr.$col -and $nr.$col.Trim() -ne '') { $e.$col = $nr.$col }
        }
      } else {
        $existing += $nr
        $index[$nr.Name] = $nr
      }
    }
    $existing | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $PkgCsv
  } else {
    $newRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $PkgCsv
  }
}

Merge-Packages -PkgCsv $PkgCsv -jobs $jobs
Good "packages.csv updated: $PkgCsv"
Good "checksums written: $Checksums"
Good "installers placed: $Installers"