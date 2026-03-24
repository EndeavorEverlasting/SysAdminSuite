param(
  [string]$ListPath   = "C:\Temp\hostlist.txt",
  [string]$OutputPath = "C:\Temp\MachineInfo.csv",
  [int]$Throttle      = 15
)

$Computers = Get-Content -Path $ListPath |
  Where-Object { $_ -and $_.Trim() -ne "" } |
  ForEach-Object { $_.Trim() } |
  Sort-Object -Unique

if (-not $Computers) { throw "No hosts found in $ListPath." }

function Start-MachineQueryJob {
  param([string]$Computer)

  Start-Job -Name "MI_$Computer" -ScriptBlock {
    param($Computer)

    function Get-MonitorSerials {
      param([string]$Computer)
      try {
        $eds = Get-WmiObject -Namespace root\wmi -Class WmiMonitorID -ComputerName $Computer -ErrorAction Stop
        if ($eds) {
          $eds | ForEach-Object {
            ($_.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ''
          } | Where-Object { $_ -and $_.Trim() -ne '' }
        }
      } catch { @() }
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    if (Test-Connection -ComputerName $Computer -Count 1 -Quiet) {
      try {
        $serial = (Get-WmiObject -Class Win32_BIOS -ComputerName $Computer -ErrorAction Stop).SerialNumber

        $nics   = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -ComputerName $Computer -Filter "IPEnabled=TRUE" -ErrorAction SilentlyContinue
        $ipv4s  = @()
        $macs   = @()
        foreach ($n in $nics) {
          $ip4 = ($n.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1)
          if ($ip4) { $ipv4s += $ip4 }
          if ($n.MACAddress) { $macs += $n.MACAddress }
        }

        $monSer = Get-MonitorSerials -Computer $Computer

        [pscustomobject]@{
          Timestamp      = $timestamp
          HostName       = $Computer
          Serial         = $serial
          IPAddress      = ($ipv4s -join ';')
          MACAddress     = ($macs  -join ';')
          MonitorSerials = ($monSer -join ';')
          Status         = 'OK'
          ErrorMessage   = ''
        }
      } catch {
        $errMsg = $_.Exception.Message
        [pscustomobject]@{
          Timestamp      = $timestamp
          HostName       = $Computer
          Serial         = 'Error'
          IPAddress      = ''
          MACAddress     = ''
          MonitorSerials = ''
          Status         = 'Query Failed'
          ErrorMessage   = $errMsg
        }
      }
    } else {
      [pscustomobject]@{
        Timestamp      = $timestamp
        HostName       = $Computer
        Serial         = 'Offline'
        IPAddress      = ''
        MACAddress     = ''
        MonitorSerials = ''
        Status         = 'Offline'
        ErrorMessage   = ''
      }
    }
  } -ArgumentList $Computer
}

$jobs = @()
foreach ($c in $Computers) {
  # BUG-FIX: Filter by our own jobs only so unrelated session jobs don't affect throttling
  $running = $jobs | Where-Object { $_.State -eq 'Running' }
  while (($running | Measure-Object).Count -ge $Throttle) {
    Wait-Job -Any $running | Out-Null
    $running = $jobs | Where-Object { $_.State -eq 'Running' }
  }
  $jobs += Start-MachineQueryJob -Computer $c
}

if ($jobs) { Wait-Job -Job $jobs | Out-Null }

$results = $jobs | Receive-Job
$dir = Split-Path -Path $OutputPath -Parent
if ([string]::IsNullOrWhiteSpace($dir)) { $dir = (Get-Location).Path }
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$results | Sort-Object HostName | Export-Csv -Path $OutputPath -NoTypeInformation

$jobs | Remove-Job -Force | Out-Null
Write-Host "Done. Output saved to $OutputPath" -ForegroundColor Green