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

function Preflight-Repo {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $installers = Join-Path $RepoRoot 'installers'
  $checksums  = Join-Path $RepoRoot 'checksums'
  $pkgCsv     = Join-Path $RepoRoot 'packages.csv'
  $fetchMap   = Join-Path $RepoRoot 'fetch-map.csv'
  $sourcesCsv = Join-Path $RepoRoot 'sources.csv'

  foreach($d in @($installers,$checksums)){
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  }

  $warns = @()
  if (-not (Test-Path $sourcesCsv)) { $warns += "Missing sources.csv -> $sourcesCsv (run: New-SourcesTemplate -RepoRoot `"$RepoRoot`")" }
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
    RepoRoot   = $RepoRoot
    Installers = Join-Path $RepoRoot 'installers'
    Checksums  = Join-Path $RepoRoot 'checksums'
    PkgCsv     = Join-Path $RepoRoot 'packages.csv'
    FetchMap   = Join-Path $RepoRoot 'fetch-map.csv'
    SourcesCsv = Join-Path $RepoRoot 'sources.csv'
  }

  foreach($k in $paths.Keys){
    if ($k -in @('PkgCsv','FetchMap','SourcesCsv')) { continue } # files optional
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

  $path = Join-Path $RepoRoot 'sources.csv'
  if (Test-Path $path) { Write-Host "sources.csv already exists: $path" -ForegroundColor Yellow; return }
  @"
Name,Source,Repo,Strategy,Version,UrlTemplate,AssetRegex,FileNameTemplate,Type,SilentArgs,DetectType,DetectValue,AddToPath,PostInstall,AllowDomains
Google Chrome,url,,latest,,"https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi",,,msi,"/qn /norestart",regkey,HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome,,
Git for Windows,github,git-for-windows/git,latest,,,"Git-.*-64-bit\.exe",{{asset}},exe,"/VERYSILENT /NORESTART",file,"C:\Program Files\Git\bin\git.exe","C:\Program Files\Git\bin",
GitHub CLI,github,cli/cli,pinned,2.60.1,,"gh_{{version}}_windows_amd64\.msi",gh_{{version}}_windows_amd64.msi,msi,"/qn /norestart",file,"C:\Program Files\GitHub CLI\gh.exe",,
"@ | Set-Content -Path $path -Encoding UTF8
  Write-Host "Created starter sources.csv at: $path" -ForegroundColor Green
}

function Rebuild-FetchMap {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$SourcesCsv = (Join-Path $RepoRoot 'sources.csv'),
    [string[]]$AllowList = @("api.github.com","github.com","objects.githubusercontent.com","dl.google.com","download.visualstudio.microsoft.com","aka.ms","python.org","www.python.org","obsidian.md","githubusercontent.com"),
    [switch]$WhatIf
  )
  if (-not (Test-Path $SourcesCsv)) { throw "Missing sources.csv at $SourcesCsv (run: New-SourcesTemplate -RepoRoot `"$RepoRoot`")" }
  $src = Import-Csv $SourcesCsv
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  $rows = foreach($r in $src){
    $name=$r.Name; $url=$null; $file=$null
    $source = ($r.Source ?? 'url').ToLower()
    $strategy = ($r.Strategy ?? 'pinned').ToLower()

    switch ($source) {
      'github' {
        if (-not $r.Repo) { throw "Row '$name': Repo required for Source=github" }
        $rel = Resolve-GitHubRelease -Repo $r.Repo -Strategy $strategy -Version $r.Version
        $asset = $rel.assets | Where-Object { $_.name -match $r.AssetRegex } | Select-Object -First 1
        if (-not $asset) { throw "Row '$name': no asset matched '$($r.AssetRegex)' in $($r.Repo) [tag $($rel.tag_name)]" }
        $url  = $asset.browser_download_url
        $file = if ($r.FileNameTemplate -and $r.FileNameTemplate -match '{{version}}') {
                  $r.FileNameTemplate -replace '\{\{version\}\}', $rel.tag_name.TrimStart('v')
                } elseif ($r.FileNameTemplate) { $r.FileNameTemplate } else { $asset.name }
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