<#
PS-HangTriage.ps1 — v1.1
- Enumerates all powershell.exe + pwsh.exe (visible first, then headless fallback)
- Hang snapshot per PID (CPU%, waits, threads, TCP states, I/O)
- Rolling usage samples per PID (CPU%, WS/PM, I/O deltas, handles)
- Writes summary.csv + hang-<pid>.json + watch-<pid>.csv to OutDir\<stamp>\
#>

[CmdletBinding()]
param(
  [int]$DurationSec = 30,
  [int]$IntervalSec = 1,
  [string]$OutDir = "$env:ProgramData\SysAdminSuite\Mapping\hang"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PSProcList {
  param([switch]$IncludeHeadless)
  $procs = Get-Process powershell,pwsh -ErrorAction SilentlyContinue
  if (-not $IncludeHeadless) { $procs = $procs | Where-Object { $_.MainWindowTitle } }
  foreach ($p in $procs) {
    $wmi = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue
    [pscustomobject]@{
      PID     = $p.Id
      Name    = $p.ProcessName
      Title   = $p.MainWindowTitle
      Command = $wmi.CommandLine
    }
  }
}

function Get-PSHangReport {
  param([Parameter(Mandatory)][int]$Id)

  $p  = Get-Process -Id $Id -ErrorAction Stop
  $ci = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "IDProcess=$Id" -ErrorAction SilentlyContinue

  $snap = [pscustomobject]@{
    Time    = (Get-Date)
    PID     = $p.Id
    Name    = $p.ProcessName
    Title   = $p.MainWindowTitle
    Respond = $p.Responding
    CPU_s   = [double]::Parse(('{0:n3}' -f $p.CPU))
    CPUpct  = if($ci){ [double]$ci.PercentProcessorTime } else { [double]::NaN }
    WS_MB   = [int]($p.WorkingSet64/1MB)
    PM_MB   = [int]($p.PrivateMemorySize64/1MB)
    Handles = $p.Handles
    Threads = $p.Threads.Count
    IOR_MB  = [math]::Round($p.IOReadBytes/1MB,1)
    IOW_MB  = [math]::Round($p.IOWriteBytes/1MB,1)
    IOO_MB  = [math]::Round($p.IOOtherBytes/1MB,1)
  }

  $tw = $p.Threads | Group-Object WaitReason | Sort-Object Count -Desc |
        Select-Object @{n='WaitReason';e={$_.Name}}, Count
  $topT = $p.Threads | Sort-Object TotalProcessorTime -Desc |
          Select-Object -First 5 Id, TotalProcessorTime, PriorityLevel, ThreadState, WaitReason
  $tcp = Get-NetTCPConnection -OwningProcess $Id -ErrorAction SilentlyContinue |
         Group-Object State | Sort-Object Count -Desc |
         Select-Object @{n='TCPState';e={$_.Name}}, Count

  $hint =
    if ([double]::IsNaN($snap.CPUpct)) { 'No perf counters (CIM blocked?)' }
    elseif ($snap.CPUpct -gt 50)       { 'CPU-bound (tight loop/runaway)' }
    elseif ($tw | Where-Object {$_.WaitReason -match 'IOCompletion|PageIn|Suspended'}) { 'Waiting on I/O (disk/net/pipe) or suspended' }
    elseif ($tcp | Where-Object {$_.TCPState -in 'SYN_SENT','CLOSE_WAIT','TIME_WAIT'}) { 'Likely socket stall (remote slow/closed)' }
    elseif (-not $snap.Respond)        { 'Window nonresponsive—sync call or message pump blocked' }
    else                               { 'Low CPU + waits → external dependency or idle' }

  [pscustomobject]@{
    Summary     = $snap
    ThreadWaits = $tw
    TopThreads  = $topT
    TCPStates   = $tcp
    Hint        = $hint
  }
}

function Watch-PSUsage {
  param([Parameter(Mandatory)][int]$Id, [int]$DurationSec, [int]$IntervalSec)
  $cores = [Environment]::ProcessorCount
  $ticks = [math]::Max(1, [int]($DurationSec / $IntervalSec))
  $data  = New-Object System.Collections.Generic.List[object]
  for ($i=0; $i -lt $ticks; $i++) {
    try { $a = Get-Process -Id $Id -ErrorAction Stop } catch { break }
    Start-Sleep -Seconds $IntervalSec
    try { $b = Get-Process -Id $Id -ErrorAction Stop } catch { break }
    $data.Add([pscustomobject]@{
      Time     = (Get-Date).ToString('HH:mm:ss')
      PID      = $Id
      CPU_pct  = [math]::Round((($b.CPU - $a.CPU)/$IntervalSec) * 100 / $cores, 1)
      WS_MB    = [int]($b.WorkingSet64/1MB)
      PM_MB    = [int]($b.PrivateMemorySize64/1MB)
      IOR_kBps = [int](($b.IOReadBytes  - $a.IOReadBytes)/$IntervalSec/1KB)
      IOW_kBps = [int](($b.IOWriteBytes - $a.IOWriteBytes)/$IntervalSec/1KB)
      IOO_kBps = [int](($b.IOOtherBytes - $a.IOOtherBytes)/$IntervalSec/1KB)
      Handles  = $b.Handles
      Threads  = $b.Threads.Count
    }) | Out-Null
  }
  $data
}

# -------- run --------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$root  = Join-Path $OutDir $stamp
$null  = New-Item -ItemType Directory -Path $root -Force

$procs = Get-PSProcList
if (-not $procs) {
  Write-Host "No visible PS consoles. Including headless hosts..." -ForegroundColor Yellow
  $procs = Get-PSProcList -IncludeHeadless
}
if (-not $procs) {
  $msg = "No powershell.exe/pwsh.exe processes found."
  $stub = Join-Path $root 'summary.csv'
  "Message`n$msg" | Set-Content -Path $stub -Encoding UTF8
  Write-Host $msg -ForegroundColor Yellow
  return
}

$summary = New-Object System.Collections.Generic.List[object]

foreach ($proc in $procs | Sort-Object PID) {
  Write-Host "`n=== PID $($proc.PID) | $($proc.Name) ===" -ForegroundColor Cyan
  if ($proc.Title)   { Write-Host $proc.Title -ForegroundColor DarkCyan }
  if ($proc.Command) { Write-Host ($proc.Command -replace '\s+',' ') -ForegroundColor DarkGray }

  try { $rep = Get-PSHangReport -Id $proc.PID } catch {
    $rep = [pscustomobject]@{
      Summary     = [pscustomobject]@{ Time=(Get-Date); PID=$proc.PID; Name=$proc.Name; Title=$proc.Title; Respond=$false; CPU_s=0; CPUpct=[double]::NaN; WS_MB=0; PM_MB=0; Handles=0; Threads=0; IOR_MB=0; IOW_MB=0; IOO_MB=0 }
      ThreadWaits = @()
      TopThreads  = @()
      TCPStates   = @()
      Hint        = "Snapshot failed: $($_.Exception.Message)"
    }
  }

  $rep.Summary | Format-Table Time, PID, Name, CPUpct, WS_MB, PM_MB, Handles, Threads -AutoSize
  if ($rep.Hint) { Write-Host ("Hint: " + $rep.Hint) -ForegroundColor Yellow }

  $json = Join-Path $root ("hang-{0}.json" -f $proc.PID)
  $rep  | ConvertTo-Json -Depth 6 | Set-Content -Path $json -Encoding UTF8

  $watch = Watch-PSUsage -Id $proc.PID -DurationSec $DurationSec -IntervalSec $IntervalSec
  $watchCsv = Join-Path $root ("watch-{0}.csv" -f $proc.PID)
  if ($watch.Count) {
    $watch | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $watchCsv
  } else {
    "Message`nNo samples captured (process exited or access denied)." |
      Set-Content -Path $watchCsv -Encoding UTF8
  }

  $summary.Add([pscustomobject]@{
    PID     = $rep.Summary.PID
    Name    = $rep.Summary.Name
    Title   = $rep.Summary.Title
    CPUpct  = $rep.Summary.CPUpct
    WS_MB   = $rep.Summary.WS_MB
    PM_MB   = $rep.Summary.PM_MB
    Handles = $rep.Summary.Handles
    Threads = $rep.Summary.Threads
    Hint    = $rep.Hint
    HangJSON= (Split-Path $json -Leaf)
    WatchCSV= (Split-Path $watchCsv -Leaf)
  }) | Out-Null
}

$sumPath = Join-Path $root 'summary.csv'
if ($summary.Count) {
  $summary | Sort-Object CPUpct -Descending |
    Export-Csv -NoTypeInformation -Encoding UTF8 -Path $sumPath
} else {
  "Message`nNo rows generated (unexpected). Investigate upstream filtering." |
    Set-Content -Path $sumPath -Encoding UTF8
}

Write-Host "`nSaved to: $root" -ForegroundColor Green
Get-ChildItem $root | Format-Table Name, Length, LastWriteTime -AutoSize
