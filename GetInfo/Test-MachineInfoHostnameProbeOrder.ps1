param(
  [string]$ListPath = "C:\Temp\hostlist.txt",
  [string]$OutputPath = (Join-Path $PSScriptRoot 'Output\MachineInfo\MachineInfo_HostnameFirst_ProbeOrder.csv')
)

if (-not (Test-Path -Path $ListPath)) { throw "List file not found: $ListPath" }

$hosts = @(Get-Content -Path $ListPath |
  Where-Object { $_ -and $_.Trim() -ne '' } |
  ForEach-Object { $_.Trim() } |
  Sort-Object -Unique)

function Get-NativeToolPath {
  param([Parameter(Mandatory)][string]$ToolName)
  try { return (Get-Command $ToolName -ErrorAction Stop).Source } catch { return $null }
}

function Invoke-NativeCommand {
  param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @())
  $lines = @(); $exitCode = $null; $err = ''
  try {
    $lines = & $FilePath @Arguments 2>&1 | ForEach-Object { "$($_)" }
    $exitCode = $LASTEXITCODE
  } catch {
    $err = $_.Exception.Message
    $lines += $err
  }
  [pscustomobject]@{
    ExitCode = $exitCode
    Output = @($lines)
    Text = ((@($lines) | Where-Object { $_ }) -join ' | ')
    Error = $err
  }
}

function Get-NmapPortSummary {
  param([string[]]$Lines)
  $parts = @()
  foreach ($line in @($Lines)) {
    if ($line -match '^\s*(135|139|445|3389|5985|5986)/tcp\s+(open|closed|filtered|unfiltered|open\|filtered|closed\|filtered)\b') {
      $parts += ("{0}:{1}" -f $matches[1], $matches[2])
    }
  }
  ($parts | Sort-Object) -join ';'
}

$nmapPath = Get-NativeToolPath -ToolName 'nmap.exe'
$nltestPath = Get-NativeToolPath -ToolName 'nltest.exe'
$wmicPath = Get-NativeToolPath -ToolName 'wmic.exe'

Write-Host "[ORDER] Starting hostname probe-order checks for $($hosts.Count) host(s)." -ForegroundColor Cyan
Write-Host "[ORDER] Required host order: 01_NMAP -> 02_ACTIVE_DIRECTORY -> 03_SCCM -> 04_OTHER_NATIVE_PROBES" -ForegroundColor Cyan

$rows = @()
$total = $hosts.Count
$index = 0
foreach ($hostName in $hosts) {
  $index++
  $percent = if ($total -gt 0) { [int](($index / $total) * 100) } else { 100 }
  Write-Progress -Activity 'Hostname probe-order checks' -Status "[$index/$total] $hostName" -PercentComplete $percent
  Write-Host "[ORDER][$index/$total] Checking $hostName" -ForegroundColor Cyan

  $nmapProbe = ''
  $adProbe = ''
  $sccmProbe = ''
  $reasons = @()

  Write-Host "  [01_NMAP] $hostName" -ForegroundColor Gray
  if ($nmapPath) {
    $nmap = Invoke-NativeCommand -FilePath $nmapPath -Arguments @('-sT','-Pn','--system-dns','-p','135,139,445,3389,5985,5986', $hostName)
    $summary = Get-NmapPortSummary -Lines $nmap.Output
    if ($summary) { $nmapProbe = "01_NMAP: $summary" } else { $nmapProbe = '01_NMAP_FAIL: no parseable port states'; $reasons += $nmapProbe }
  } else {
    $nmapProbe = '01_NMAP_FAIL: nmap.exe not available'
    $reasons += $nmapProbe
  }
  Write-Host "    $nmapProbe" -ForegroundColor DarkGray

  Write-Host "  [02_ACTIVE_DIRECTORY] $hostName" -ForegroundColor Gray
  if ($nltestPath) {
    $ad = Invoke-NativeCommand -FilePath $nltestPath -Arguments @('/dsgetdc:nslijhs.net')
    if ($ad.ExitCode -eq 0 -and $ad.Text -match 'nslijhs\.net') { $adProbe = '02_ACTIVE_DIRECTORY: nslijhs.net domain controller reachable' }
    else { $adProbe = '02_ACTIVE_DIRECTORY_WARN: domain controller not confirmed'; $reasons += $adProbe }
  } else {
    $adProbe = '02_ACTIVE_DIRECTORY_WARN: nltest.exe not available'
    $reasons += $adProbe
  }
  Write-Host "    $adProbe" -ForegroundColor DarkGray

  Write-Host "  [03_SCCM] $hostName" -ForegroundColor Gray
  if ($wmicPath) {
    $sccm = Invoke-NativeCommand -FilePath $wmicPath -Arguments @("/node:$hostName", 'service', 'where', "name='ccmexec'", 'get', 'Name,State', '/value')
    if ($sccm.Text -match 'Name\s*=\s*ccmexec') { $sccmProbe = '03_SCCM: ccmexec service evidence present' }
    else { $sccmProbe = '03_SCCM_WARN: ccmexec not confirmed; continue with caution' }
  } else {
    $sccmProbe = '03_SCCM_WARN: wmic.exe not available for SCCM check'
  }
  Write-Host "    $sccmProbe" -ForegroundColor DarkGray

  $status = if ($reasons.Count -eq 0) { 'ORDER_PROBE_OK' } else { 'ORDER_PROBE_WARN' }
  if ($status -eq 'ORDER_PROBE_OK') { Write-Host "[ORDER][$index/$total] Completed $hostName: $status" -ForegroundColor Green }
  else { Write-Warning "[ORDER][$index/$total] Completed $hostName: $status - $($reasons -join ' || ')" }

  $rows += [pscustomobject]@{
    HostName = $hostName
    ProbeOrder = '01_NMAP -> 02_ACTIVE_DIRECTORY -> 03_SCCM -> 04_OTHER_NATIVE_PROBES'
    NmapProbe = $nmapProbe
    ActiveDirectoryProbe = $adProbe
    SccmProbe = $sccmProbe
    Status = $status
    Reason = ($reasons -join ' || ')
  }
}
Write-Progress -Activity 'Hostname probe-order checks' -Completed

$outDir = Split-Path -Path $OutputPath -Parent
if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = (Get-Location).Path }
if (-not (Test-Path $outDir)) { New-Item -Path $outDir -ItemType Directory -Force | Out-Null }
$rows | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "[ORDER] Hostname probe-order evidence saved to $OutputPath" -ForegroundColor Green
