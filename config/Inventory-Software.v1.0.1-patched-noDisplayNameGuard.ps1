<#  Inventory-Software.ps1
    Export installed software from HKLM (32/64) to CSV+HTML per host.
    Defaults to local machine; supports remoting.
    Writes to: <RepoRoot>\inventory\<HOST>\installed_software_<HOST>.csv|html
    Also builds/refreshes: <RepoRoot>\inventory\software_superset.csv
#>

[CmdletBinding()]
param(
  [string[]]$ComputerName = $env:COMPUTERNAME,
  [string]$RepoHost = $env:REPO_HOST,
  [switch]$NoMerge  # skip superset build
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- load tools + resolve repo ---
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Join-Path $here 'GoLiveTools.ps1'
if (-not (Test-Path $tools)) { throw "Missing GoLiveTools.ps1 at $tools" }
. $tools -RepoHost $RepoHost   # prints banner & exposes $RepoRoot
try {
  Preflight-Repo -RepoRoot $RepoRoot | Out-Null
  Write-Host ("Preflight OK ⇒ {0}" -f $RepoRoot) -ForegroundColor Green
} catch {
  Write-Host ("Preflight FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
  throw
}

# --- helpers ---
$inventoryRoot = Join-Path $RepoRoot 'inventory'
New-Item -ItemType Directory -Force -Path $inventoryRoot | Out-Null

$arpRoots = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

$scriptBlock = {
  param($arpRoots)
  $ErrorActionPreference = 'Continue'
  $rows = foreach($r in $arpRoots){
    Get-ChildItem $r | ForEach-Object {
      $p = Get-ItemProperty $_.PSPath
      if ($p.DisplayName) {
        [pscustomobject]@{
          Host            = $env:COMPUTERNAME
          DisplayName     = [string]$p.DisplayName
          DisplayVersion  = [string]$p.DisplayVersion
          Publisher       = [string]$p.Publisher
          InstallDate     = [string]$p.InstallDate
          InstallLocation = [string]$p.InstallLocation
          Uninstall       = [string]$p.UninstallString
          QuietUninstall  = [string]$p.QuietUninstallString
          ProductCode     = [string]$p.PSChildName
          RegistryPath    = $_.PSPath
        }
      }
    }
  }
  $rows | Sort-Object DisplayName, DisplayVersion -Descending `
       | Group-Object DisplayName `
       | ForEach-Object { $_.Group | Select-Object -First 1 }
}

# --- gather per host ---
$all = @()
foreach($cn in $ComputerName){
  try{
    if ($cn -ieq $env:COMPUTERNAME) {
      $rows = & $scriptBlock $arpRoots
    } else {
      $rows = Invoke-Command -ComputerName $cn -ScriptBlock $scriptBlock -ArgumentList (,$arpRoots)
    }
    if (-not $rows) { Write-Warning "No rows for $cn (no access or empty)"; continue }

    $hostDir = Join-Path $inventoryRoot $cn
    New-Item -ItemType Directory -Force -Path $hostDir | Out-Null

    $csv  = Join-Path $hostDir ("installed_software_{0}.csv"  -f $cn)
    $html = Join-Path $hostDir ("installed_software_{0}.html" -f $cn)

    $rows | Sort-Object DisplayName | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    $rows | Sort-Object DisplayName | ConvertTo-Html -Title "Software on $cn" | Out-File -FilePath $html -Encoding UTF8

    Write-Host "Wrote $csv"  -ForegroundColor Green
    Write-Host "Wrote $html" -ForegroundColor Green
    $all += $rows
  }
  catch {
    Write-Warning "Failed to inventory $($cn): $($_.Exception.Message)"
  }
}

# --- superset merge (one row per product, presence flags by host) ---
if (-not $NoMerge -and $all.Count) {
  $superset = $all | Group-Object DisplayName | ForEach-Object {
    $name = $_.Name
    $latest = $_.Group | Sort-Object DisplayVersion -Descending | Select-Object -First 1
    $row = [ordered]@{
      Name          = $name
      Publisher     = $latest.Publisher
      Version_hint  = $latest.DisplayVersion
    }
    foreach($cn in $ComputerName){
      $row["On_$cn"] = [bool]($_.Group | Where-Object { $_.Host -eq $cn })
    }
    # keep raw detection anchors for later mapping
    $row["DetectType"]  = if ($latest.ProductCode -match '^\{?[0-9A-F-]{32,}\}?$') { 'productcode' } else { 'regkey' }
    $row["DetectValue"] = if ($row.DetectType -eq 'productcode') { $latest.ProductCode } else { ($latest.RegistryPath -replace '^Registry::','' -replace 'HKLM:\\','HKLM\') }
    [pscustomobject]$row
  }

  $supCsv = Join-Path $inventoryRoot 'software_superset.csv'
  $superset | Sort-Object Name | Export-Csv -Path $supCsv -NoTypeInformation -Encoding UTF8
  Write-Host "Wrote superset => $supCsv" -ForegroundColor Cyan
}

Write-Host "Inventory complete." -ForegroundColor Green

