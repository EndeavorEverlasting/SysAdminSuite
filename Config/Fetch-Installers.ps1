<#
Fetch-Installers.ps1 - vendor-only fetcher with backbone.
Reads fetch-map.csv -> downloads installers -> writes checksums -> updates packages.csv.
No winget. Parallel, retried, verified, and loud.

CSV schema (fetch-map.csv):
Name,Url,FileName,Type,SilentArgs,DetectType,DetectValue,AddToPath,PostInstall,AllowDomains

Notes:
- AllowDomains (optional) is semicolon-separated and augments -AllowList.
- Run this on a box with internet; target RepoRoot may be local path or UNC.

Examples:
  .\Fetch-Installers.ps1 -RepoRoot \\SERVER\SoftwareRepo -DryRun
  .\Fetch-Installers.ps1 -RepoRoot \\SERVER\SoftwareRepo -MaxParallel 4
  .\Fetch-Installers.ps1 -RepoRoot C:\SoftwareRepo -Only "Google Chrome","PowerShell 7-x64"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$RepoRoot,                           # e.g. C:\SoftwareRepo OR \\HOST\SoftwareRepo
  [string]$FetchMap = ".\fetch-map.csv",
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

# --- Load plan --------------------------------------------------------------
if (-not (Test-Path $FetchMap)) { Fail "Missing fetch-map: $FetchMap" }
$rows = Import-Csv $FetchMap
if ($Only) { $rows = $rows | Where-Object { $Only -contains $_.Name } }
$rows = $rows | Where-Object { $_.Url -and $_.FileName -and $_.Type }  # minimal validation
if (-not $rows -or $rows.Count -eq 0) { Fail "Nothing to do. Check your filters or fetch-map content." }

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