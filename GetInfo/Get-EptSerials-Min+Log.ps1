<# =====================================================================
  Get-EptSerials-Min+Log.ps1
  Purpose: Sweep WNY075EPT### and return ONLY:
           - PCSerial (Win32_BIOS.SerialNumber, fallback to ComputerSystemProduct)
           - MonitorSerials (active monitors via WmiMonitorID; ';' separated)

  Outputs:
    1) serials_YYYYMMDD-HHmm.csv        -> Hostname, PCSerial, MonitorSerials
    2) serials_YYYYMMDD-HHmm.log        -> Human-readable log with timestamps
    3) serials_YYYYMMDD-HHmm.jsonl      -> One JSON object per host (for grep/jq)
    4) serials_YYYYMMDD-HHmm.unresolved -> Hostnames with empty PCSerial
===================================================================== #>

[CmdletBinding()]
param(
  [string]$Prefix     = "WNY075EPT",
  [int]   $Start      = 1,
  [int]   $End        = 180,
  [int]   $Digits     = 3,
  [int]   $TimeoutSec = 4,
  [string]$OutputDir  = ".",
  [string]$LogDir     = $null,    # default: OutputDir
  [pscredential]$Credential,
  [switch]$SkipPing,              # use if ICMP is blocked
  [ValidateSet('INFO','DEBUG')]
  [string]$LogLevel = 'INFO'
)

# -------------------- bootstrap --------------------
$ts = Get-Date -Format "yyyyMMdd-HHmm"
if (-not $LogDir) { $LogDir = $OutputDir }

$OutCsv  = Join-Path $OutputDir "serials_$ts.csv"
$OutLog  = Join-Path $LogDir    "serials_$ts.log"
$OutJnl  = Join-Path $LogDir    "serials_$ts.jsonl"
$OutMiss = Join-Path $LogDir    "serials_$ts.unresolved"

$null = New-Item -ItemType Directory -Path $OutputDir -Force -ErrorAction SilentlyContinue
$null = New-Item -ItemType Directory -Path $LogDir    -Force -ErrorAction SilentlyContinue

# -------------------- logging helpers --------------------
$script:Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
function Write-Log {
  param([string]$Level, [string]$Msg)
  if ($Level -eq 'DEBUG' -and $LogLevel -ne 'DEBUG') { return }
  $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Msg
  Add-Content -Path $OutLog -Value $line
}
function Write-Jsonl {
  param([hashtable]$Obj)
  $json = ($Obj | ConvertTo-Json -Depth 6 -Compress)
  Add-Content -Path $OutJnl -Value $json
}

Write-Log INFO  "=== Run start: Prefix=$Prefix Range=$Start..$End TimeoutSec=$TimeoutSec ==="
Write-Log INFO  "Output CSV: $OutCsv"
Write-Log INFO  "Logs: $OutLog, $OutJnl"
if ($SkipPing) { Write-Log INFO "SkipPing: TRUE" }
if ($LogLevel -eq 'DEBUG') { Write-Log DEBUG "Debug logging enabled" }

# -------------------- utils --------------------
function New-TargetName { param([int]$n) return ("{0}{1}" -f $Prefix, $n.ToString("D$Digits")) }

function Decode-MonitorSerials {
  param($wmiMonitorId)  # instances of root\wmi:WmiMonitorID
  $out = @()
  foreach ($m in @($wmiMonitorId)) {
    if (-not $m) { continue }
    $chars = $m.SerialNumberID | ForEach-Object { if ($_ -gt 0) { [char]$_ } }
    $s = (-join $chars).Trim()
    if ($s) { $out += $s }
  }
  return $out
}

# -------------------- core --------------------
$targets = foreach ($i in $Start..$End) { New-TargetName $i }

$rows        = New-Object System.Collections.Generic.List[object]
$unresolved  = New-Object System.Collections.Generic.List[string]
$stats = [ordered]@{
  Total            = $targets.Count
  PingSkipped      = 0
  PingOffline      = 0
  CimOk            = 0
  CimError         = 0
  PcSerialMissing  = 0
  MonitorsFound    = 0
}

foreach ($t in $targets) {
  Write-Log DEBUG "Host ${t}: begin"

  # reachability
  $reachable = $true
  if (-not $SkipPing) {
    $reachable = Test-Connection -TargetName $t -Count 1 -Quiet -TimeoutSeconds 1
    if (-not $reachable) {
      $stats.PingOffline++
      Write-Log INFO  "Host ${t}: offline (ping)."
      $row = [pscustomobject]@{ Hostname=$t; PCSerial=$null; MonitorSerials=$null }
      $rows.Add($row) | Out-Null
      Write-Jsonl @{ Hostname=$t; Stage='Ping'; Reachable=$false; Error='Offline' }
      if (-not $row.PCSerial) { $unresolved.Add($t) | Out-Null }
      continue
    }
  } else {
    $stats.PingSkipped++
  }

  # CIM
  $sess = $null
  $pcSerial = $null
  $monSer   = $null
  try {
    $sessOpts = New-CimSessionOption -Protocol Dcom
    $sessArgs = @{ ComputerName = $t; SessionOption = $sessOpts; ErrorAction = 'Stop' }
    if ($Credential) { $sessArgs.Credential = $Credential }
    $sess = New-CimSession @sessArgs

    # PC serial
    $bios = Get-CimInstance -Class Win32_BIOS -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction Stop
    $pcSerial = $bios.SerialNumber
    if ([string]::IsNullOrWhiteSpace($pcSerial)) {
      $csp = Get-CimInstance -Class Win32_ComputerSystemProduct -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction SilentlyContinue
      if ($csp) { $pcSerial = $csp.IdentifyingNumber }
    }

    # Monitor serials
    try {
      $mon = Get-CimInstance -Namespace root\wmi -Class WmiMonitorID -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction Stop |
             Where-Object { $_.Active -eq $true }
      $ms = Decode-MonitorSerials $mon
      if ($ms.Count -gt 0) {
        $monSer = ($ms -join '; ')
        $stats.MonitorsFound += $ms.Count
      }
    } catch {
      Write-Log DEBUG ("Host {0}: monitor query failed: {1}" -f $t, ($_.Exception.Message -replace '\r|\n',' '))
    }

    $stats.CimOk++
    Write-Log INFO ("Host {0}: OK  PCSerial='{1}'  Monitors='{2}'" -f $t, ($pcSerial ?? ''), ($monSer ?? ''))
    Write-Jsonl @{ Hostname=$t; Stage='CIM'; Reachable=$true; PCSerial=$pcSerial; MonitorSerials=$monSer }
  }
  catch {
    $stats.CimError++
    $err = ($_.Exception.Message -replace '\r|\n',' ').Trim()
    Write-Log INFO ("Host {0}: CIM-ERROR {1}" -f $t, $err)
    Write-Jsonl @{ Hostname=$t; Stage='CIM'; Reachable=$true; Error=$err }
  }
  finally {
    if ($sess) { $sess | Remove-CimSession }
  }

  $row = [pscustomobject]@{
    Hostname       = $t
    PCSerial       = $pcSerial
    MonitorSerials = $monSer
  }
  $rows.Add($row) | Out-Null
  if (-not $pcSerial) { $unresolved.Add($t) | Out-Null }
}

# -------------------- outputs --------------------
$rows | Select-Object Hostname, PCSerial, MonitorSerials |
  Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8

$unresolved | Sort-Object | Set-Content -Path $OutMiss -Encoding UTF8

$script:Stopwatch.Stop()
$elapsed = "{0:n1}s" -f $script:Stopwatch.Elapsed.TotalSeconds
Write-Log INFO  "=== Summary ==="
Write-Log INFO  ("Total={0}  PingSkipped={1}  PingOffline={2}  CimOk={3}  CimError={4}  PcSerialMissing={5}  MonitorsFound={6}" -f `
                 $stats.Total, $stats.PingSkipped, $stats.PingOffline, $stats.CimOk, $stats.CimError, $unresolved.Count, $stats.MonitorsFound)
Write-Log INFO  "Unresolved list: $OutMiss"
Write-Log INFO  "CSV: $OutCsv"
Write-Log INFO  "Elapsed: $elapsed"
Write-Host      "CSV: $OutCsv"
Write-Host      "Log: $OutLog"
Write-Host      "JSONL: $OutJnl"
Write-Host      "Unresolved: $OutMiss"
Write-Host      "Elapsed: $elapsed"
