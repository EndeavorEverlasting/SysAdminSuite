<#
.SYNOPSIS
  Collect spreadsheet-ready rows for EPT devices: old/new names, PC serial,
  second-monitor serial (if any), attached peripherals summary, renamed flag,
  and labeled location.

.OUTPUT
  survey_ept_YYYYMMDD-HHmm.csv with columns:
    Old PC Names, New PC Name, Serial number, Monitor#2 Serial number,
    Peripherals attached, Renamed, Labeled location
#>

[CmdletBinding()]
param(
  [string]$Prefix     = "WNY075EPT", # expected naming prefix
  [int]   $Start      = 1,
  [int]   $End        = 180,
  [int]   $Digits     = 3,
  [int]   $TimeoutSec = 4,
  [string]$OutputDir  = ".",
  [string]$LabeledLocation = "75 Rockefeller Plaza – 8F Epic Training Suite",
  [pscredential]$Credential,
  [switch]$SkipPing,     # use if ICMP is blocked
  [switch]$VerbosePeripherals # emit longer peripheral list
)

# ---------- helpers ----------
function New-TargetName { param([int]$n) return ("{0}{1}" -f $Prefix, $n.ToString("D$Digits")) }

function Join-Clip {
  param([string[]]$Items, [int]$MaxLen = 120)
  $s = ($Items | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique) -join "; "
  if ($s.Length -gt $MaxLen) { return $s.Substring(0, $MaxLen) + "…" } else { return $s }
}

function Decode-MonitorSerial {
  param($wmiMonitorId) # WmiMonitorID instance(s)
  if (-not $wmiMonitorId) { return @() }
  $serials = @()
  foreach ($m in $wmiMonitorId) {
    $chars = $m.SerialNumberID | ForEach-Object { if ($_ -gt 0) { [char]$_ } }
    $serials += -join $chars
  }
  return $serials | Where-Object { $_ -and $_.Trim() }
}

function Get-RowForHost {
  param([string]$Computer)

  $row = [ordered]@{
    'Old PC Names'            = $null
    'New PC Name'             = $Computer
    'Serial number'           = $null      # PC/Chassis serial
    'Monitor#2 Serial number' = $null      # if a second monitor exists
    'Peripherals attached'    = $null
    'Renamed'                 = $null      # TRUE if current name == expected
    'Labeled location'        = $LabeledLocation
  }

  # Reachability gate
  if (-not $SkipPing) {
    $alive = Test-Connection -TargetName $Computer -Count 1 -Quiet -TimeoutSeconds 1
    if (-not $alive) {
      $row.'Renamed' = ''
      return $row
    }
  }

  # CimSession over DCOM
  $sessOpts = New-CimSessionOption -Protocol Dcom
  $sessArgs = @{ ComputerName=$Computer; SessionOption=$sessOpts; ErrorAction='Stop' }
  if ($Credential) { $sessArgs.Credential = $Credential }
  $sess = $null
  try {
    $sess = New-CimSession @sessArgs

    # Names/OS/BIOS
    $cs   = Get-CimInstance -Class Win32_ComputerSystem   -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction Stop
    $bios = Get-CimInstance -Class Win32_BIOS             -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction Stop
    $csp  = Get-CimInstance -Class Win32_ComputerSystemProduct -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction SilentlyContinue

    $row.'Old PC Names'  = $cs.Name
    $serial = $bios.SerialNumber
    if ([string]::IsNullOrWhiteSpace($serial) -and $csp) { $serial = $csp.IdentifyingNumber }
    $row.'Serial number' = $serial

    # Renamed? (does current equals expected)
    $row.'Renamed' = [bool]($cs.Name -eq $Computer)

    # Monitors (root\wmi)
    try {
      $mon = Get-CimInstance -Namespace root\wmi -Class WmiMonitorID -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction Stop |
             Where-Object { $_.Active -eq $true }
      $ms = Decode-MonitorSerial $mon
      if ($ms.Count -ge 2) { $row.'Monitor#2 Serial number' = $ms[1] }
      elseif ($ms.Count -eq 1) { $row.'Monitor#2 Serial number' = "" } # only 1 monitor
    } catch { $row.'Monitor#2 Serial number' = "" }

    # Peripherals (summarize human-useful things)
    try {
      $devs = Get-CimInstance -ClassName Win32_PnPEntity -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction Stop |
              Where-Object {
                $_.PNPClass -in @('Keyboard','Mouse','HIDClass','Bluetooth','Image','Media','Biometric') -or
                ($_.Name -match 'Dock|ThinkPad|USB-C Hub|DisplayLink|Webcam|SmartCard')
              } |
              Select-Object -ExpandProperty Name
      if (-not $VerbosePeripherals) {
        # compress to categories
        $cats = @()
        if ($devs -match 'Keyboard')     { $cats += 'Keyboard' }
        if ($devs -match 'Mouse')        { $cats += 'Mouse' }
        if ($devs -match 'Webcam|Camera'){ $cats += 'Webcam' }
        if ($devs -match 'Bluetooth')    { $cats += 'Bluetooth' }
        if ($devs -match 'SmartCard')    { $cats += 'SmartCard' }
        if ($devs -match 'DisplayLink|Dock|Hub') { $cats += 'Dock/Hub' }
        $row.'Peripherals attached' = if ($cats) { ($cats -join ', ') } else { '' }
      } else {
        $row.'Peripherals attached' = Join-Clip -Items $devs
      }
    } catch { $row.'Peripherals attached' = "" }

  } catch {
    # unreachable via CIM -> leave blanks; you’ll walk these
  } finally {
    if ($sess) { $sess | Remove-CimSession }
  }

  return $row
}

# ---------- main ----------
$targets = foreach ($i in $Start..$End) { New-TargetName $i }
$ts      = Get-Date -Format "yyyyMMdd-HHmm"
$outCsv  = Join-Path $OutputDir "survey_ept_$ts.csv"

$rows = foreach ($t in $targets) { Get-RowForHost -Computer $t }

# Ensure column order matches the sheet exactly
$selectOrder = 'Old PC Names','New PC Name','Serial number','Monitor#2 Serial number','Peripherals attached','Renamed','Labeled location'
$rows | Select-Object $selectOrder |
  Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8

Write-Host "Wrote: $outCsv"
