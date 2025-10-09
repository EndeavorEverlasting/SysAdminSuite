<#  Inventory-Software.patched.ps1
    Export installed software from HKLM (32/64) to CSV+HTML per host.
    Writes to: <RepoRoot>\inventory\<HOST>\installed_software_<HOST>.csv|html
    Also builds/refreshes: <RepoRoot>\inventory\software_superset.csv
#>

[CmdletBinding()]
param(
  [string[]]$ComputerName = @($env:COMPUTERNAME),
  [string]  $RepoHost     = $env:REPO_HOST,
  [switch]  $NoMerge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- load tools + resolve repo ---
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Join-Path $here 'GoLiveTools.ps1'
if (-not (Test-Path $tools)) { throw "Missing GoLiveTools.ps1 at $tools" }
. $tools -RepoHost $RepoHost   # prints banner, exposes $RepoRoot

# --- prep inventory root ---
$inventoryRoot = Join-Path $RepoRoot 'inventory'
New-Item -ItemType Directory -Force -Path $inventoryRoot | Out-Null

$arpRoots = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

# scriptblock that runs on local/remote to scrape ARP rows
$scriptBlock = {
  param($arpRoots)
  $ErrorActionPreference = 'SilentlyContinue'
  $rows = foreach($root in $arpRoots){
    if (-not (Test-Path $root)) { continue }
    foreach($k in Get-ChildItem $root){
      $p = Get-ItemProperty -Path $k.PSPath
      # Safely read DisplayName; missing props return $null via PSObject lookup
      $dn = ($p.PSObject.Properties['DisplayName'] | Select-Object -ExpandProperty Value -ErrorAction SilentlyContinue)
      if ([string]::IsNullOrWhiteSpace($dn)) { continue }
      [pscustomobject]@{
        Name        = $dn.Trim()
        Version     = (($p.PSObject.Properties['DisplayVersion'])?.Value)
        Publisher   = (($p.PSObject.Properties['Publisher'])?.Value)
        InstallDate = (($p.PSObject.Properties['InstallDate'])?.Value)
        Uninstall   = (($p.PSObject.Properties['UninstallString'])?.Value)
        ProductCode = $p.PSChildName
        RegistryKey = $k.Name
      }
    }
  }
  $rows
}

$perHost = @()

foreach($cn in $ComputerName){
  try {
    $isLocal = $cn -eq $env:COMPUTERNAME
    $rows = if ($isLocal) {
      & $scriptBlock -arpRoots $arpRoots
    } else {
      Invoke-Command -ComputerName $cn -ScriptBlock $scriptBlock -ArgumentList ($arpRoots)
    }

    if (-not $rows) { $rows = @() }

    # normalize and dedupe (prefer ones with versions)
    $norm = $rows |
      Where-Object { $_.Name -and $_.Name -notmatch 'Update for Windows' } |
      Sort-Object Name, Version -Descending |
      Group-Object Name | ForEach-Object {
        $winner = $_.Group | Sort-Object @{e={$_.Version -as [version]};Descending=$true}, Version -Descending | Select-Object -First 1
        [pscustomobject]@{
          Name        = $_.Name
          Version     = $winner.Version
          Publisher   = $winner.Publisher
          InstallDate = $winner.InstallDate
          DetectType  = if ($winner.ProductCode -match '^\{?[0-9A-F-]{32,}\}?$') { 'productcode' } else { 'regkey' }
          DetectValue = if ($winner.ProductCode -match '^\{?[0-9A-F-]{32,}\}?$') { $winner.ProductCode } else { $winner.RegistryKey -replace '^Registry::','' -replace 'HKLM:\\','HKLM\' }
        }
      }

    # write per-host CSV + HTML
    $hostDir = Join-Path $inventoryRoot $cn
    New-Item -ItemType Directory -Force -Path $hostDir | Out-Null
    $csv = Join-Path $hostDir ("installed_software_{0}.csv"  -f $cn)
    $html= Join-Path $hostDir ("installed_software_{0}.html" -f $cn)
    $norm | Sort-Object Name | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    $norm | Sort-Object Name | ConvertTo-Html -Title ("Installed Software - {0}" -f $cn) | Set-Content -Encoding UTF8 $html
    Write-Host ("Wrote {0} items => {1}" -f ($norm.Count), $csv) -ForegroundColor Cyan

    $perHost += [pscustomobject]@{ Host=$cn; Items=$norm }
  }
  catch {
    Write-Warning ("Failed to inventory {0}: {1}" -f $cn, $_.Exception.Message)
  }
}

if (-not $NoMerge) {
  # Guard: if no host produced rows, skip superset to avoid .Items null errors
  if (-not $perHost -or -not ($perHost | Where-Object { <#  Inventory-Software.patched.ps1
    Export installed software from HKLM (32/64) to CSV+HTML per host.
    Writes to: <RepoRoot>\inventory\<HOST>\installed_software_<HOST>.csv|html
    Also builds/refreshes: <RepoRoot>\inventory\software_superset.csv
#>

[CmdletBinding()]
param(
  [string[]]$ComputerName = @($env:COMPUTERNAME),
  [string]  $RepoHost     = $env:REPO_HOST,
  [switch]  $NoMerge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- load tools + resolve repo ---
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Join-Path $here 'GoLiveTools.ps1'
if (-not (Test-Path $tools)) { throw "Missing GoLiveTools.ps1 at $tools" }
. $tools -RepoHost $RepoHost   # prints banner, exposes $RepoRoot

# --- prep inventory root ---
$inventoryRoot = Join-Path $RepoRoot 'inventory'
New-Item -ItemType Directory -Force -Path $inventoryRoot | Out-Null

$arpRoots = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

# scriptblock that runs on local/remote to scrape ARP rows
$scriptBlock = {
  param($arpRoots)
  $ErrorActionPreference = 'SilentlyContinue'
  $rows = foreach($root in $arpRoots){
    if (-not (Test-Path $root)) { continue }
    foreach($k in Get-ChildItem $root){
      $p = Get-ItemProperty -Path $k.PSPath
      # Safely read DisplayName; missing props return $null via PSObject lookup
      $dn = ($p.PSObject.Properties['DisplayName'] | Select-Object -ExpandProperty Value -ErrorAction SilentlyContinue)
      if ([string]::IsNullOrWhiteSpace($dn)) { continue }
      [pscustomobject]@{
        Name        = $dn.Trim()
        Version     = (($p.PSObject.Properties['DisplayVersion'])?.Value)
        Publisher   = (($p.PSObject.Properties['Publisher'])?.Value)
        InstallDate = (($p.PSObject.Properties['InstallDate'])?.Value)
        Uninstall   = (($p.PSObject.Properties['UninstallString'])?.Value)
        ProductCode = $p.PSChildName
        RegistryKey = $k.Name
      }
    }
  }
  $rows
}

$perHost = @()

foreach($cn in $ComputerName){
  try {
    $isLocal = $cn -eq $env:COMPUTERNAME
    $rows = if ($isLocal) {
      & $scriptBlock -arpRoots $arpRoots
    } else {
      Invoke-Command -ComputerName $cn -ScriptBlock $scriptBlock -ArgumentList ($arpRoots)
    }

    if (-not $rows) { $rows = @() }

    # normalize and dedupe (prefer ones with versions)
    $norm = $rows |
      Where-Object { $_.Name -and $_.Name -notmatch 'Update for Windows' } |
      Sort-Object Name, Version -Descending |
      Group-Object Name | ForEach-Object {
        $winner = $_.Group | Sort-Object @{e={$_.Version -as [version]};Descending=$true}, Version -Descending | Select-Object -First 1
        [pscustomobject]@{
          Name        = $_.Name
          Version     = $winner.Version
          Publisher   = $winner.Publisher
          InstallDate = $winner.InstallDate
          DetectType  = if ($winner.ProductCode -match '^\{?[0-9A-F-]{32,}\}?$') { 'productcode' } else { 'regkey' }
          DetectValue = if ($winner.ProductCode -match '^\{?[0-9A-F-]{32,}\}?$') { $winner.ProductCode } else { $winner.RegistryKey -replace '^Registry::','' -replace 'HKLM:\\','HKLM\' }
        }
      }

    # write per-host CSV + HTML
    $hostDir = Join-Path $inventoryRoot $cn
    New-Item -ItemType Directory -Force -Path $hostDir | Out-Null
    $csv = Join-Path $hostDir ("installed_software_{0}.csv"  -f $cn)
    $html= Join-Path $hostDir ("installed_software_{0}.html" -f $cn)
    $norm | Sort-Object Name | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    $norm | Sort-Object Name | ConvertTo-Html -Title ("Installed Software - {0}" -f $cn) | Set-Content -Encoding UTF8 $html
    Write-Host ("Wrote {0} items => {1}" -f ($norm.Count), $csv) -ForegroundColor Cyan

    $perHost += [pscustomobject]@{ Host=$cn; Items=$norm }
  }
  catch {
    Write-Warning ("Failed to inventory {0}: {1}" -f $cn, $_.Exception.Message)
  }
}

# --- Build superset across hosts (guarded) ---
if (-not $NoMerge) {
  # Guard: only proceed if we have host rows
  $hostsWithItems = $perHost | Where-Object { $_ -and $_.PSObject.Properties['Items'] -and $_.Items }
  if (-not $hostsWithItems) {
    Write-Warning "No host inventory rows were produced; skipping superset."
    return
  }

  # Collect unique names from all hosts
  $names = $hostsWithItems.Items |
           ForEach-Object { $_ } |
           Select-Object -ExpandProperty Name -Unique |
           Sort-Object

  $superset = foreach ($name in $names) {
    $latest = $null
    $row = [ordered]@{
      Name      = $name
      Version   = $null
      Publisher = $null
    }

    foreach ($h in $hostsWithItems) {
      $hit = $h.Items | Where-Object { $_.Name -eq $name } | Select-Object -First 1
      $row["On_{0}" -f $h.Host] = [bool]$hit
      if ($hit -and -not $latest) { $latest = $hit }
    }

    if ($latest) {
      $row.Version     = $latest.Version
      $row.Publisher   = $latest.Publisher
      $row.DetectType  = $latest.DetectType
      $row.DetectValue = $latest.DetectValue
    }

    [pscustomobject]$row
  }

  $supCsv = Join-Path $inventoryRoot 'software_superset.csv'
  $superset | Sort-Object Name | Export-Csv -Path $supCsv -NoTypeInformation -Encoding UTF8
  Write-Host "Wrote superset => $supCsv" -ForegroundColor Green
}


Write-Host "Inventory complete." -ForegroundColor Green

.Items })){
    Write-Warning "No host inventory rows were produced; skipping superset."
    return
  }

  # build a superset across all hosts
  $names = $perHost.Items | ForEach-Object { $_ } | Select-Object -ExpandProperty Name -Unique | Sort-Object
  $superset = foreach($name in $names){
    $latest = $null
    $row = [ordered]@{
      Name    = $name
      Version = $null
      Publisher = $null
    }
    foreach($h in $perHost){
      $hit = $h.Items | Where-Object { $_.Name -eq $name } | Select-Object -First 1
      $row["On_{0}" -f $h.Host] = [bool]$hit
      if ($hit -and -not $latest) { $latest = $hit }
    }
    if ($latest){
      $row.Version   = $latest.Version
      $row.Publisher = $latest.Publisher
      $row["DetectType"]  = $latest.DetectType
      $row["DetectValue"] = $latest.DetectValue
    }
    [pscustomobject]$row
  }

  $supCsv = Join-Path $inventoryRoot 'software_superset.csv'
  $superset | Sort-Object Name | Export-Csv -Path $supCsv -NoTypeInformation -Encoding UTF8
  Write-Host "Wrote superset => $supCsv" -ForegroundColor Green
}

Write-Host "Inventory complete." -ForegroundColor Green


