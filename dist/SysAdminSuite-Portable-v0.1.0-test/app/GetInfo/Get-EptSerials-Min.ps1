<# =====================================================================
  Get-EptSerials-Min.ps1
  Purpose: For hostnames WNY075EPT###, return ONLY:
           - PCSerial (chassis/BIOS serial)
           - MonitorSerials (all active monitors, ';' separated)
  Output: serials_YYYYMMDD-HHmm.csv  with columns:
          Hostname, PCSerial, MonitorSerials
===================================================================== #>

[CmdletBinding()]
param(
  [string]$Prefix     = "WNY075EPT",
  [int]   $Start      = 1,
  [int]   $End        = 180,
  [int]   $Digits     = 3,
  [int]   $TimeoutSec = 4,
  [string]$OutputDir  = ".",
  [pscredential]$Credential,
  [switch]$SkipPing   # use if ICMP is blocked
)

# -------------------- helpers --------------------
function New-TargetName { param([int]$n) return ("{0}{1}" -f $Prefix, $n.ToString("D$Digits")) }

function Decode-MonitorSerials {
  param($wmiMonitorId)  # instances of root\wmi:WmiMonitorID
  if (-not $wmiMonitorId) { return @() }
  $out = @()
  foreach ($m in $wmiMonitorId) {
    $chars = $m.SerialNumberID | ForEach-Object { if ($_ -gt 0) { [char]$_ } }
    $s = (-join $chars).Trim()
    if ($s) { $out += $s }
  }
  return $out
}

function Get-HostSerials {
  param([string]$Computer)

  $result = [ordered]@{
    Hostname        = $Computer
    PCSerial        = $null
    MonitorSerials  = $null
  }

  # quick reachability (optional)
  if (-not $SkipPing) {
    if (-not (Test-Connection -TargetName $Computer -Count 1 -Quiet -TimeoutSeconds 1)) {
      return [pscustomobject]$result  # unreachable -> blank row
    }
  }

  # CIM session over DCOM (works on domain boxes w/out WinRM)
  $sess = $null
  try {
    $sessOpts = New-CimSessionOption -Protocol Dcom
    $sessArgs = @{ ComputerName = $Computer; SessionOption = $sessOpts; ErrorAction = 'Stop' }
    if ($Credential) { $sessArgs.Credential = $Credential }
    $sess = New-CimSession @sessArgs

    # PC serial: Win32_BIOS.SerialNumber, fallback to Win32_ComputerSystemProduct.IdentifyingNumber
    $bios = Get-CimInstance -Class Win32_BIOS -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction Stop
    $pcSerial = $bios.SerialNumber
    if ([string]::IsNullOrWhiteSpace($pcSerial)) {
      $csp = Get-CimInstance -Class Win32_ComputerSystemProduct -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction SilentlyContinue
      if ($csp) { $pcSerial = $csp.IdentifyingNumber }
    }
    $result.PCSerial = $pcSerial

    # Monitor serials: root\wmi:WmiMonitorID where Active = $true
    try {
      $mon = Get-CimInstance -Namespace root\wmi -Class WmiMonitorID -CimSession $sess -OperationTimeoutSec $TimeoutSec -ErrorAction Stop |
             Where-Object { $_.Active -eq $true }
      $ms = Decode-MonitorSerials $mon
      if ($ms.Count -gt 0) { $result.MonitorSerials = ($ms -join '; ') }
    } catch {
      # leave blank if class not available or access denied
    }

  } catch {
    # leave row blank if CIM fails; you'll walk it
  } finally {
    if ($sess) { $sess | Remove-CimSession }
  }

  return [pscustomobject]$result
}

# -------------------- main --------------------
$targets = foreach ($i in $Start..$End) { New-TargetName $i }
$ts = Get-Date -Format "yyyyMMdd-HHmm"
$outCsv = Join-Path $OutputDir "serials_$ts.csv"

$rows = foreach ($t in $targets) { Get-HostSerials -Computer $t }

# EXACTLY the three columns requested
$rows | Select-Object Hostname, PCSerial, MonitorSerials |
  Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8

Write-Host "Wrote: $outCsv"
