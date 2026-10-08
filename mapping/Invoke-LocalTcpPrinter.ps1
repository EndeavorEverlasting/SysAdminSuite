<#
.SYNOPSIS
  Deterministic local Windows TCP/IP printer workflow (NOT Northwell shared-queue mapping).
.DESCRIPTION
  Read-only Plan, operator-authorized Apply and test-page submission.
  Never treats a stale saved IP, successful TCP connection, or DNS alone as proof of
  physical device identity. A fresh operator-observed panel IPv4 address is required
  before any mapping mutation. A hostname-backed port is preferred when DNS agrees
  with the panel; an IP-backed recovery requires explicit override.
  Receipts are private local state, never repository artifacts.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Plan','Apply','TestPage')][string]$Mode,
  [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PrinterName,
  [string]$HostOrAddress = '',
  [string]$PanelAddress = '',
  [string]$DriverName = '',
  [switch]$PanelConfirmed,
  [switch]$UsePanelAddress
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail([string]$Code, [string]$Reason) {
  throw [System.InvalidOperationException]::new("[$Code] $Reason")
}
function Get-IPv4([string]$Value) {
  $parsed = $null
  if (-not [System.Net.IPAddress]::TryParse($Value, [ref]$parsed)) { return $null }
  if ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $null }
  if ($parsed.Equals([System.Net.IPAddress]::Any) -or $parsed.Equals([System.Net.IPAddress]::Broadcast)) { return $null }
  return $parsed.ToString()
}
function Test-Tcp9100([string]$Address) {
  $socket = New-Object System.Net.Sockets.TcpClient
  try {
    $async = $socket.BeginConnect($Address, 9100, $null, $null)
    if (-not $async.AsyncWaitHandle.WaitOne(2500, $false)) { return $false }
    $socket.EndConnect($async)
    return $socket.Connected
  } catch { return $false }
  finally { $socket.Close() }
}
function Resolve-Target([string]$Host, [string]$Panel, [bool]$Override) {
  if ([string]::IsNullOrWhiteSpace($Host)) { Fail 'TARGET_REQUIRED' 'Enter the device hostname or IPv4 address.' }
  if ($Host.Length -gt 253 -or $Host -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]*$') {
    Fail 'INVALID_TARGET' 'Use an IPv4 address or DNS hostname, not a URL or print-server queue.'
  }
  $direct = Get-IPv4 $Host
  $resolved = @()
  if ($direct) {
    $resolved = @($direct)
  } else {
    try {
      $resolved = @([System.Net.Dns]::GetHostAddresses($Host) |
        Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
        ForEach-Object { $_.ToString() } | Select-Object -Unique)
    } catch { $resolved = @() }
  }
  if ($resolved.Count -gt 1) {
    Fail 'AMBIGUOUS_DNS' 'The hostname resolves to more than one IPv4 address. Inspect DNS; do not guess.'
  }
  $dnsIp = if ($resolved.Count -eq 1) { [string]$resolved[0] } else { '' }
  $panelIp = if ($Panel) { Get-IPv4 $Panel } else { $null }
  if ($Panel -and -not $panelIp) { Fail 'INVALID_PANEL_ADDRESS' 'Panel address must be a valid IPv4 address.' }
  if ($Override -and -not $panelIp) { Fail 'PANEL_ADDRESS_REQUIRED' 'IP recovery requires the address observed on the device panel.' }
  if ($Override) {
    return [pscustomobject]@{
      Ip = $panelIp; PortAddress = $panelIp; Resolution = 'OPERATOR_PANEL_OVERRIDE'
      DnsAddress = $dnsIp
    }
  }
  if (-not $dnsIp) {
    Fail 'DNS_UNRESOLVED' 'Hostname did not resolve. Confirm the device panel IP, then explicitly choose panel-IP recovery.'
  }
  if ($panelIp -and $dnsIp -ne $panelIp) {
    Fail 'DNS_PANEL_MISMATCH' "DNS returned $dnsIp but device panel says $panelIp. Use explicitly confirmed panel-IP recovery or repair DNS."
  }
  return [pscustomobject]@{
    Ip = $dnsIp; PortAddress = $(if ($direct) { $dnsIp } else { $Host })
    Resolution = $(if ($direct) { 'DIRECT_IPV4' } else { 'MATCHED_HOSTNAME' })
    DnsAddress = $dnsIp
  }
}
function Get-PortName([string]$Address) {
  $normalized = ($Address -replace '[^A-Za-z0-9.-]', '_').ToUpperInvariant()
  return 'SAS_LOCAL_TCP_' + $normalized
}
function Record-Result([pscustomobject]$Data) {
  $root = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\PrinterMapping\runs'
  if (-not (Test-Path -LiteralPath $root)) {
    [void](New-Item -ItemType Directory -Path $root -Force)
  }
  $file = Join-Path $root ('local-tcp-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N')))
  $Data | Add-Member -NotePropertyName ReceiptPath -NotePropertyValue $file -Force
  $json = $Data | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText($file, $json, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output $json
}
$result = [pscustomobject]@{
  SchemaVersion = 'sas-local-tcp-printer-run/v1'
  Mode = $Mode
  State = 'STARTED'
  PrinterName = $PrinterName
  HostOrAddress = $HostOrAddress
  PanelAddress = $PanelAddress
  ResolvedAddress = ''
  DnsAddress = ''
  PortAddress = ''
  PortName = ''
  DriverName = $DriverName
  Resolution = ''
  Changed = $false
  Reason = ''
  ObservedPhysicalOutput = $false
  Timestamp = (Get-Date).ToUniversalTime().ToString('o')
}
try {
  if ($PrinterName.Length -gt 120 -or $PrinterName -match '[\\/:*?"<>|]' -or [string]::IsNullOrWhiteSpace($PrinterName)) {
    Fail 'INVALID_PRINTER_NAME' 'Printer name is empty or contains unsupported characters.'
  }
  $existing = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
  if ($Mode -eq 'TestPage') {
    if (-not $existing) { Fail 'QUEUE_NOT_FOUND' 'The queue is not installed.' }
    if ($existing.PortName -notlike 'SAS_LOCAL_TCP_*') {
      Fail 'QUEUE_NOT_MANAGED' 'Refusing to submit a test page to an unrelated queue.'
    }
    & rundll32.exe 'printui.dll,PrintUIEntry' '/k' '/n' $PrinterName
    $result.State = 'TEST_PAGE_SUBMITTED'
    $result.Reason = 'Submission is not proof of physical output. Confirm the page at the device.'
  } else {
    if (-not $DriverName) { Fail 'DRIVER_REQUIRED' 'Select an installed print driver.' }
    if (-not (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue)) {
      Fail 'DRIVER_NOT_INSTALLED' 'Selected driver is not installed; do not silently substitute another.'
    }
    $resolved = Resolve-Target -Host $HostOrAddress -Panel $PanelAddress -Override ([bool]$UsePanelAddress)
    $result.ResolvedAddress = $resolved.Ip
    $result.DnsAddress = $resolved.DnsAddress
    $result.PortAddress = $resolved.PortAddress
    $result.Resolution = $resolved.Resolution
    $result.PortName = Get-PortName $resolved.PortAddress
    if (-not (Test-Tcp9100 $resolved.Ip)) {
      Fail 'TCP_9100_UNREACHABLE' 'TCP 9100 did not respond. Check network, SSID, VPN, current device IP and print protocol.'
    }
    if ($existing -and $existing.PortName -notlike 'SAS_LOCAL_TCP_*') {
      Fail 'UNMANAGED_QUEUE_CONFLICT' 'A printer with this name exists but is not owned by this local TCP workflow.'
    }
    if ($existing -and $existing.DriverName -ne $DriverName) {
      Fail 'DRIVER_CONFLICT' 'Existing queue uses another driver. Review it before changing anything.'
    }
    $port = Get-PrinterPort -Name $result.PortName -ErrorAction SilentlyContinue
    if ($port -and ($port.PrinterHostAddress -ne $resolved.PortAddress -or [int]$port.PortNumber -ne 9100)) {
      Fail 'PORT_NAME_CONFLICT' 'Existing port name points somewhere else. No port will be repurposed.'
    }
    if ($Mode -eq 'Plan') {
      $result.State = if ($existing -and $existing.PortName -eq $result.PortName) { 'ALREADY_MAPPED' } else { 'READY_TO_MAP' }
      $result.Reason = 'Read-only preview; Apply requires fresh physical panel confirmation.'
    } else {
      $panelIp = Get-IPv4 $PanelAddress
      if (-not $PanelConfirmed -or -not $panelIp) {
        Fail 'PANEL_CONFIRMATION_REQUIRED' 'Read the current address on the actual printer and confirm it in the app.'
      }
      if ($panelIp -ne $resolved.Ip) {
        Fail 'IDENTITY_NOT_CONFIRMED' 'Panel address does not match the exact IP selected for mapping.'
      }
      $createdPort = $false
      $createdQueue = $false
      $oldPort = if ($existing) { [string]$existing.PortName } else { '' }
      try {
        if (-not $port) {
          Add-PrinterPort -Name $result.PortName -PrinterHostAddress $resolved.PortAddress -PortNumber 9100 -ErrorAction Stop
          $createdPort = $true
        }
        if (-not $existing) {
          Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $result.PortName -ErrorAction Stop
          $createdQueue = $true
        } elseif ($existing.PortName -ne $result.PortName) {
          Set-Printer -Name $PrinterName -PortName $result.PortName -ErrorAction Stop
        }
        $after = Get-Printer -Name $PrinterName -ErrorAction Stop
        if ($after.DriverName -ne $DriverName -or $after.PortName -ne $result.PortName) {
          Fail 'POSTCONDITION_FAILED' 'Installed queue/driver/port does not match the approved plan.'
        }
        $result.Changed = $createdQueue -or $createdPort -or ($oldPort -ne $result.PortName)
        $result.State = if ($result.Changed) { 'MAPPED_NOW' } else { 'ALREADY_MAPPED' }
        $result.Reason = 'Queue registration verified; physical print acceptance requires an observed test page.'
      } catch {
        $originalError = $_.Exception.Message
        $rollbackError = ''
        try {
          if ($createdQueue) { Remove-Printer -Name $PrinterName -ErrorAction Stop }
          elseif ($existing -and $oldPort -and $oldPort -ne $result.PortName) {
            Set-Printer -Name $PrinterName -PortName $oldPort -ErrorAction Stop
          }
          if ($createdPort -and -not @(Get-Printer | Where-Object { $_.PortName -eq $result.PortName }).Count) {
            Remove-PrinterPort -Name $result.PortName -ErrorAction Stop
          }
        } catch { $rollbackError = $_.Exception.Message }
        if ($rollbackError) { Fail 'ROLLBACK_INCOMPLETE' "$originalError | Rollback: $rollbackError" }
        Fail 'MAPPING_FAILED_ROLLED_BACK' $originalError
      }
    }
  }
} catch {
  $result.State = 'FAILED'
  $result.Reason = $_.Exception.Message
}
try { Record-Result $result }
catch {
  Write-Error ('RECEIPT_WRITE_FAILED: ' + $_.Exception.Message)
  exit 2
}
if ($result.State -eq 'FAILED') { exit 1 }
