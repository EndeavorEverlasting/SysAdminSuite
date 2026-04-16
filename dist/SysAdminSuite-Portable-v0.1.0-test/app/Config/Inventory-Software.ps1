<# Inventory-Software.v1.1.4-DisplayNameSafe+Preflight.ps1
CHANGES:
- Superset discovery: use -Recurse + -Filter from $inventoryRoot (no wildcard Join-Path).
- Keep $TargetHost (avoid $Host collision) and context-aware Resolve-SASContext.
- Note: $PSScriptRoot works only inside scripts (documented).
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

function Resolve-SASContext {
  param([string]$PreferredRepoRoot,[string]$PreferredRepoHost)
  $anchor =
    if     ($PSCommandPath) { Split-Path -Parent $PSCommandPath }
    elseif ($PSScriptRoot)  { $PSScriptRoot } # valid here (inside script)
    elseif ($psEditor -and $psEditor.GetEditorContext()) { Split-Path -Parent ($psEditor.GetEditorContext().CurrentFile.Path) }
    else { (Get-Location).Path }
  $cur = Get-Item -LiteralPath $anchor
  while ($cur -and -not (Test-Path (Join-Path $cur.FullName 'config'))) { $cur = $cur.Parent }
  if (-not $cur) { throw "Could not resolve SysAdminSuite root from '$anchor'." }
  $SASRoot    = $cur.FullName
  $ConfigRoot = Join-Path $SASRoot 'config'
  $RepoRoot   =
    if     ($PreferredRepoRoot) { $PreferredRepoRoot }
    elseif ($env:REPO_ROOT)     { $env:REPO_ROOT }
    elseif ($PreferredRepoHost) { "\\$PreferredRepoHost\SoftwareRepo" }
    elseif (Test-Path (Join-Path $SASRoot 'SoftwareRepo')) { Join-Path $SASRoot 'SoftwareRepo' }
    else { 'C:\SoftwareRepo' }
  foreach($p in @($RepoRoot,(Join-Path $RepoRoot 'inventory'))) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
  [pscustomobject]@{ SASRoot=$SASRoot; ConfigRoot=$ConfigRoot; RepoRoot=$RepoRoot }
}

function Ensure-Directory { param([Parameter(Mandatory)][string]$Path) if (-not (Test-Path $Path -PathType Container)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }

function Normalize-Row {
  # BUG-FIX: $Host is a PS built-in automatic variable. Renamed to $HostName to avoid collision.
  param([Parameter(Mandatory,ValueFromPipeline)][object]$Row,[string]$HostName)
  process{
    $need='Name','Version','Publisher','UninstallString','InstallLocation','DisplayName','DisplayVersion','Host','DetectType','DetectValue','InstallDate','Timestamp'
    foreach($c in $need){ if(-not ($Row.PSObject.Properties.Name -contains $c)){ $Row | Add-Member -NotePropertyName $c -NotePropertyValue $null } }
    if(-not $Row.Name){$Row.Name=$Row.DisplayName}; if(-not $Row.Version){$Row.Version=$Row.DisplayVersion}
    if(-not $Row.Host){$Row.Host=$HostName}; if(-not $Row.Timestamp){$Row.Timestamp=(Get-Date).ToString('s')}
    $Row
  }
}

function TryVersion { param([string]$v) try{[version]$v}catch{$null} }
function Pick-Best { param([Parameter(Mandatory)][object[]]$Rows)
  if (-not $Rows -or $Rows.Count -eq 0) { return $null }
  $withParsed=foreach($r in $Rows){[pscustomobject]@{Row=$r;Parsed=(TryVersion $r.Version)}}
  $c=$withParsed|Where-Object Parsed|Sort-Object Parsed -Descending
  if($c){return $c[0].Row}; $w=$Rows|Where-Object Version; if($w){return $w[0]}; return $Rows[0]
}

#---------------- preflight ----------------#
$ctx=Resolve-SASContext -PreferredRepoRoot $RepoRoot -PreferredRepoHost $RepoHost
$resolvedRepoRoot=$ctx.RepoRoot
$inventoryRoot=Join-Path $resolvedRepoRoot 'inventory'
Ensure-Directory -Path $inventoryRoot
Write-Host ("Using RepoRoot: {0}" -f $resolvedRepoRoot) -ForegroundColor Cyan

# ARP hives
$arpRoots=@(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

# Collector (avoid $Host collision)
# NOTE: Uses foreach loop (not ForEach-Object pipeline) so that individual
# item errors under StrictMode -Version Latest + ErrorActionPreference Stop
# do not terminate the entire pipeline.  Property access is guarded with
# PSObject.Properties checks to avoid "property not found" strict-mode errors.
$collector={
  param([string[]]$arpRoots,[string]$TargetHost)
  $script:InventoryErrorCount = 0
  foreach($root in $arpRoots){
    try {
      $regItems = @(Get-ChildItem -Path $root -ErrorAction Stop)
      foreach ($regItem in $regItems) {
        try {
          $it = Get-ItemProperty -Path $regItem.PSPath -ErrorAction Stop
          $dn = if ($it.PSObject.Properties['DisplayName']) { "$($it.DisplayName)".Trim() } else { '' }
          if ($dn) {
            $dv  = if ($it.PSObject.Properties['DisplayVersion'])  { "$($it.DisplayVersion)".Trim() }  else { '' }
            $pub = if ($it.PSObject.Properties['Publisher'])        { "$($it.Publisher)".Trim() }        else { '' }
            $us  = if ($it.PSObject.Properties['UninstallString'])  { "$($it.UninstallString)".Trim() }  else { '' }
            $il  = if ($it.PSObject.Properties['InstallLocation'])  { "$($it.InstallLocation)".Trim() }  else { '' }
            $id  = if ($it.PSObject.Properties['InstallDate'])      { "$($it.InstallDate)".Trim() }      else { '' }
            [pscustomobject]@{
              Name=$dn; Version=$dv; Publisher=$pub
              UninstallString=$us; InstallLocation=$il; InstallDate=$id
              DetectType='RegKey'; DetectValue=$regItem.Name; Host=$TargetHost; Timestamp=(Get-Date).ToString('s')
            }
          }
        } catch {
          $script:InventoryErrorCount++
          Write-Warning ("[{0}] Failed reading registry item: {1}" -f $TargetHost, $_.Exception.Message)
        }
      }
    } catch {
      $script:InventoryErrorCount++
      Write-Warning ("[{0}] Failed reading hive {1}: {2}" -f $TargetHost, $root, $_.Exception.Message)
    }
  }
}

#---------------- per-host export ----------------#
foreach($cn in $ComputerName){
  $TargetHost=$cn
  $hostDir=Join-Path $inventoryRoot $TargetHost; Ensure-Directory -Path $hostDir
  $csv = Join-Path $hostDir ("installed_software_{0}.csv" -f $TargetHost)
  $html=[IO.Path]::ChangeExtension($csv,'.html')

  $data= if($TargetHost -in @('localhost','127.0.0.1',$env:COMPUTERNAME)){ & $collector -arpRoots $arpRoots -TargetHost $TargetHost }
         else{ Invoke-Command -ComputerName $TargetHost -ScriptBlock $collector -ArgumentList (,$arpRoots),$TargetHost }

  if (-not $data) {
    $norm = @()
  } else {
    $norm=@($data|Normalize-Row -HostName $TargetHost)
  }
  if ($norm.Count -gt 0) {
    $norm|Sort-Object Name|Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    $suiteHtmlHelper = Join-Path $PSScriptRoot '..\tools\ConvertTo-SuiteHtml.ps1'
    if (Test-Path -LiteralPath $suiteHtmlHelper) {
      . $suiteHtmlHelper
      $norm|Select-Object Name,Version,Publisher,Host|Sort-Object Name|
        ConvertTo-Html -Fragment -PreContent '<h2>Installed Software</h2>' |
        ConvertTo-SuiteHtml -Title "Installed Software - $TargetHost" -Subtitle $TargetHost -OutputPath $html
    } else {
      $norm|Select-Object Name,Version,Publisher,Host|Sort-Object Name|
        ConvertTo-Html -Title "Installed Software - $TargetHost" | Set-Content -Path $html -Encoding UTF8
    }
  } else {
    @() | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    $suiteHtmlHelper = Join-Path $PSScriptRoot '..\tools\ConvertTo-SuiteHtml.ps1'
    if (Test-Path -LiteralPath $suiteHtmlHelper) {
      . $suiteHtmlHelper
      '<h3>No inventory data for ' + [System.Net.WebUtility]::HtmlEncode($TargetHost) + '</h3>' |
        ConvertTo-SuiteHtml -Title "Installed Software - $TargetHost" -Subtitle $TargetHost -OutputPath $html
    } else {
      "<html><body><h3>No inventory data for $TargetHost</h3></body></html>" | Set-Content -Path $html -Encoding UTF8
    }
  }
  Write-Host ("Wrote {0} items => {1}" -f ($norm.Count), $csv) -ForegroundColor Green
}

#---------------- superset merge ----------------#
if(-not $NoMerge){
  # Correct discovery (no wildcard Join-Path)
  $csvFiles = Get-ChildItem -Path $inventoryRoot -Recurse -Filter 'installed_software_*.csv' -File -ErrorAction SilentlyContinue

  $rows = foreach($f in $csvFiles){
    try{
      $r=Import-Csv -Path $f.FullName
      foreach($x in $r){
        if(-not ($x.PSObject.Properties.Name -contains 'SourceCsv')){ $x|Add-Member -NotePropertyName 'SourceCsv' -NotePropertyValue $f.FullName }
        else{ $x.SourceCsv=$f.FullName }; $x
      }
    }catch{ Write-Warning "Failed to import $($f.FullName): $($_.Exception.Message)" }
  }

  $rows = $rows | Normalize-Row -HostName '<unknown>'

  $superset = $rows | Group-Object -Property Name,Publisher | ForEach-Object { Pick-Best -Rows $_.Group }
  $supCsv = Join-Path $inventoryRoot 'software_superset.csv'
  $sorted = $superset | Sort-Object Name
  $sorted | Export-Csv -Path $supCsv -NoTypeInformation -Encoding UTF8
  Write-Host "Wrote superset => $supCsv" -ForegroundColor Green

  # ── HTML output for superset ───────────────────────────────────────
  $suiteHtmlHelper = Join-Path $PSScriptRoot '..\tools\ConvertTo-SuiteHtml.ps1'
  if (Test-Path -LiteralPath $suiteHtmlHelper) {
    . $suiteHtmlHelper
    $supHtml = [IO.Path]::ChangeExtension($supCsv, '.html')
    $sorted | Select-Object Name,Version,Publisher,Host |
      ConvertTo-Html -Fragment -PreContent '<h2>Software Superset</h2>' |
      ConvertTo-SuiteHtml -Title 'Software Superset' -Subtitle "$($sorted.Count) unique title(s)" -OutputPath $supHtml
    Write-Host "Wrote superset HTML => $supHtml" -ForegroundColor Green
  }
}

Write-Host "Inventory complete." -ForegroundColor Green