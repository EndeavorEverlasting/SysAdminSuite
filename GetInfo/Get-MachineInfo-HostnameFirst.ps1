param(
  [string]$ListPath   = "C:\Temp\hostlist.txt",
  [string]$OutputPath = (Join-Path $PSScriptRoot 'Output\MachineInfo\MachineInfo_HostnameFirst_Output.csv'),
  [int]$Throttle      = 15
)

if (-not (Test-Path -Path $ListPath)) {
  throw "List file not found: $ListPath"
}

$Computers = Get-Content -Path $ListPath |
  Where-Object { $_ -and $_.Trim() -ne "" } |
  ForEach-Object { $_.Trim() } |
  Sort-Object -Unique

if (-not $Computers) { throw "No hosts found in $ListPath." }

function Start-MachineQueryJob {
  param([string]$Computer)

  Start-Job -Name "MI_$Computer" -ScriptBlock {
    param($Computer)

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    # This hostname-first copy intentionally does not pre-resolve hostnames to IPs,
    # does not gate collection on ping, and does not export IP addresses. In large
    # routed organizations, stale DNS/DHCP records can cause one IP to appear tied
    # to multiple computer names. Serial number, MAC address, and the remote-reported
    # computer name are treated as stronger identity evidence than IP address.
    $isLocal = $Computer -eq $env:COMPUTERNAME -or
               $Computer -eq 'localhost' -or
               $Computer -eq '127.0.0.1' -or
               $Computer -eq '.'

    function New-MachineInfoRecord {
      param(
        [string]$Status,
        [string]$ErrorMessage = '',
        [string]$Serial = '',
        [string]$MACAddress = '',
        [string]$MonitorSerials = '',
        [string]$ReportedComputerName = '',
        [string]$Model = '',
        [string]$Manufacturer = '',
        [string]$IdentityWarning = ''
      )

      [pscustomobject]@{
        Timestamp            = $timestamp
        HostName             = $Computer
        ReportedComputerName = $ReportedComputerName
        Serial               = $Serial
        MACAddress           = $MACAddress
        MonitorSerials       = $MonitorSerials
        Model                = $Model
        Manufacturer         = $Manufacturer
        IdentityWarning      = $IdentityWarning
        Status               = $Status
        ErrorMessage         = $ErrorMessage
      }
    }

    function Get-TargetWmiObject {
      param(
        [Parameter(Mandatory)][string]$ClassName,
        [string]$Namespace = 'root\cimv2',
        [string]$Filter = '',
        [System.Management.Automation.ActionPreference]$ErrorActionValue = 'Stop'
      )

      $params = @{
        Class       = $ClassName
        Namespace   = $Namespace
        ErrorAction = $ErrorActionValue
      }
      if ($Filter) { $params.Filter = $Filter }
      if (-not $isLocal) { $params.ComputerName = $Computer }

      Get-WmiObject @params
    }

    function Get-MonitorSerials {
      try {
        $eds = Get-TargetWmiObject -Namespace 'root\wmi' -ClassName 'WmiMonitorID' -ErrorActionValue 'Stop'
        if ($eds) {
          $eds | ForEach-Object {
            ($_.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ''
          } | Where-Object { $_ -and $_.Trim() -ne '' }
        }
      } catch { @() }
    }

    try {
      $bios = Get-TargetWmiObject -ClassName 'Win32_BIOS' -ErrorActionValue 'Stop'
      $serial = $bios.SerialNumber

      $computerSystem = Get-TargetWmiObject -ClassName 'Win32_ComputerSystem' -ErrorActionValue 'Stop'
      $reportedName = $computerSystem.Name
      $manufacturer = $computerSystem.Manufacturer
      $model = $computerSystem.Model

      $nics = Get-TargetWmiObject -ClassName 'Win32_NetworkAdapterConfiguration' -Filter "IPEnabled=TRUE" -ErrorActionValue 'SilentlyContinue'
      $macs = @()
      foreach ($n in @($nics)) {
        if ($n.MACAddress) { $macs += $n.MACAddress }
      }

      $monSer = Get-MonitorSerials

      $identityWarning = ''
      $requestedShortName = $Computer.Split('.')[0]
      if ($reportedName -and $Computer -notin @('localhost','127.0.0.1','.') -and $reportedName.ToUpperInvariant() -ne $requestedShortName.ToUpperInvariant()) {
        $identityWarning = "Requested host '$Computer' reported itself as '$reportedName'. Check DNS or the host list before trusting this row."
      }

      New-MachineInfoRecord \
        -Status 'OK' \
        -Serial $serial \
        -MACAddress (($macs | Sort-Object -Unique) -join ';') \
        -MonitorSerials (($monSer | Sort-Object -Unique) -join ';') \
        -ReportedComputerName $reportedName \
        -Model $model \
        -Manufacturer $manufacturer \
        -IdentityWarning $identityWarning
    } catch {
      $errMsg = $_.Exception.Message
      New-MachineInfoRecord -Status 'Query Failed' -Serial 'Error' -ErrorMessage $errMsg
    }
  } -ArgumentList $Computer
}

$jobs = @()
foreach ($c in $Computers) {
  # Filter by this run's job collection so unrelated session jobs do not affect throttling.
  $runningJobs = $jobs | Where-Object { $_.State -eq 'Running' }
  while ($runningJobs.Count -ge $Throttle) {
    Wait-Job -Any $runningJobs | Out-Null
    $runningJobs = $jobs | Where-Object { $_.State -eq 'Running' }
  }
  $jobs += Start-MachineQueryJob -Computer $c
}

if ($jobs) { Wait-Job -Job $jobs | Out-Null }

$results = $jobs | Receive-Job
$dir = Split-Path -Path $OutputPath -Parent
if ([string]::IsNullOrWhiteSpace($dir)) {
  $dir = (Get-Location).Path
}
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$results | Sort-Object HostName | Export-Csv -Path $OutputPath -NoTypeInformation

$jobs | Remove-Job -Force | Out-Null
Write-Host "Done. Output saved to $OutputPath" -ForegroundColor Green

# ── HTML output ─────────────────────────────────────────────────────
$suiteHtmlHelper = Join-Path $PSScriptRoot '..\tools\ConvertTo-SuiteHtml.ps1'
if (Test-Path -LiteralPath $suiteHtmlHelper) {
  . $suiteHtmlHelper
  $htmlPath = [IO.Path]::ChangeExtension($OutputPath, '.html')
  $results | Sort-Object HostName |
    Select-Object HostName,ReportedComputerName,Serial,MACAddress,MonitorSerials,Model,Manufacturer,IdentityWarning,Status,ErrorMessage |
    ConvertTo-Html -Fragment -PreContent '<h2>Machine Info - Hostname First</h2>' |
    ConvertTo-SuiteHtml -Title 'Machine Info - Hostname First' -Subtitle "$(($results | Select-Object -ExpandProperty HostName -Unique).Count) host(s)" -OutputPath $htmlPath
}