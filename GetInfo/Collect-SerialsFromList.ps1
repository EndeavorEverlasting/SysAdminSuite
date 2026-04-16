<# =====================================================================
  Collect-SerialsFromList.ps1
  INPUT: -HostsFile path to a text file with one hostname per line
         (blank lines and lines starting with # are ignored)

  OUTPUTS (in -OutputDir, default .):
    serials_YYYYMMDD-HHmm.csv        -> Hostname,PCSerial,MonitorSerials
    serials_YYYYMMDD-HHmm.log        -> simple timestamped log
    serials_YYYYMMDD-HHmm.unresolved -> hostnames missing PCSerial

  Flags:
    -SkipPing         : skip ICMP gate (use when ping is blocked)
    -Parallel         : run in parallel (PowerShell 7+) for speed
    -ThrottleLimit N  : parallel degree (default 20)
    -TimeoutSec N     : per-host CIM timeout (default 4)
===================================================================== #>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$HostsFile,

  [int]$TimeoutSec = 4,
  [string]$OutputDir = ".",
  [pscredential]$Credential,
  [switch]$SkipPing,
  [switch]$Parallel,
  [int]$ThrottleLimit = 20
)

# ---------- Prep ----------
if (!(Test-Path -LiteralPath $HostsFile)) {
  throw "Hosts file not found: $HostsFile"
}
$ts = Get-Date -Format "yyyyMMdd-HHmm"
$OutCsv  = Join-Path $OutputDir "serials_${ts}.csv"
$OutLog  = Join-Path $OutputDir "serials_${ts}.log"
$OutMiss = Join-Path $OutputDir "serials_${ts}.unresolved"
$null = New-Item -ItemType Directory -Path $OutputDir -Force -ErrorAction SilentlyContinue

# Read hosts (trim, drop blanks/comments)
$Hosts = Get-Content -LiteralPath $HostsFile -ErrorAction Stop |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -and -not $_.StartsWith('#') } |
  Select-Object -Unique

"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [INFO] Start. Hosts=$($Hosts.Count) TimeoutSec=$TimeoutSec Parallel=$Parallel" | Add-Content $OutLog

# ---------- Core function ----------
$script:getSerials = {
  param(
    [string]$Computer,
    [int]$TimeoutSec,
    [bool]$SkipPing,
    [pscredential]$Credential
  )
  $row = [pscustomobject]@{ Hostname=$Computer; PCSerial=$null; MonitorSerials=$null; _Err=$null }

  try {
    if (-not $SkipPing) {
      $alive = Test-Connection -TargetName $Computer -Count 1 -Quiet -TimeoutSeconds 1
      if (-not $alive) {
        $row._Err = 'offline'
        return $row
      }
    }

    $sess = $null
    try {
      $sessOpt = New-CimSessionOption -Protocol Dcom
      $sessArgs = @{ ComputerName=$Computer; SessionOption=$sessOpt; ErrorAction='Stop' }
      if ($Credential) { $sessArgs.Credential = $Credential }
      $sess = New-CimSession @sessArgs

      # PC serial
      $bios = Get-CimInstance -Class Win32_BIOS -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction Stop
      $pcSerial = $bios.SerialNumber
      if ([string]::IsNullOrWhiteSpace($pcSerial)) {
        $csp = Get-CimInstance -Class Win32_ComputerSystemProduct -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction SilentlyContinue
        if ($csp) { $pcSerial = $csp.IdentifyingNumber }
      }
      $row.PCSerial = $pcSerial

      # Monitor serials via EDID decode
      try {
        $mon = Get-CimInstance -Namespace root\wmi -Class WmiMonitorID -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction Stop |
               Where-Object { $_.Active -eq $true }
        $list = @()
        foreach ($m in @($mon)) {
          $chars = $m.SerialNumberID | ForEach-Object { if ($_ -gt 0) { [char]$_ } }
          $s = (-join $chars).Trim()
          if ($s) { $list += $s }
        }
        if ($list.Count -gt 0) { $row.MonitorSerials = ($list -join '; ') }
      } catch {
        # leave blank if class unavailable
      }
    }
    finally { if ($sess) { $sess | Remove-CimSession } }
  }
  catch {
    $row._Err = ($_.Exception.Message -replace '\r|\n',' ').Trim()
  }
  return $row
}

# ---------- Execution (seq or parallel) ----------
$results = @()
if ($Parallel) {
  # thread-safe collection for results + logs
  $bag = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
  $logbag = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

  $Hosts | ForEach-Object -Parallel {
    $r = & $using:getSerials -Computer $_ -TimeoutSec $using:TimeoutSec -SkipPing $using:SkipPing -Credential $using:Credential
    $bag.Add($r)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    if ($r._Err) {
      $logbag.Add("$stamp [WARN] ${($_)} -> $($r._Err)")
    } else {
      $logbag.Add("$stamp [OK]   ${($_)} PC='$($r.PCSerial)' Mon='$($r.MonitorSerials)'")
    }
  } -ThrottleLimit $ThrottleLimit

  $results = $bag.ToArray()
  $logbag.ToArray() | Sort-Object | Add-Content -Path $OutLog
}
else {
  foreach ($h in $Hosts) {
    $r = & $script:getSerials -Computer $h -TimeoutSec $TimeoutSec -SkipPing $SkipPing -Credential $Credential
    if ($r._Err) {
      "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [WARN] ${h} -> $($r._Err)" | Add-Content $OutLog
    } else {
      "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [OK]   ${h} PC='$($r.PCSerial)' Mon='$($r.MonitorSerials)'" | Add-Content $OutLog
    }
    $results += $r
  }
}

# ---------- Write outputs ----------
$results | Select-Object Hostname, PCSerial, MonitorSerials |
  Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8

$results | Where-Object { -not $_.PCSerial } | Select-Object -ExpandProperty Hostname |
  Sort-Object | Set-Content -Path $OutMiss -Encoding UTF8

"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [INFO] Done. CSV=$OutCsv  Unresolved=$OutMiss" | Add-Content $OutLog
Write-Host "CSV: $OutCsv"
Write-Host "Log: $OutLog"
Write-Host "Unresolved: $OutMiss"
