[CmdletBinding(DefaultParameterSetName='Probe')]
param(
  [Parameter(ParameterSetName='Probe')]
  [string[]]$Targets,

  [Parameter(ParameterSetName='Probe')]
  [string]$ListPath,

  [Parameter(ParameterSetName='Probe')]
  [string]$OutCsv = (Join-Path $PSScriptRoot 'Output\KronosClock\KronosClockInventory.csv'),

  [Parameter(ParameterSetName='Lookup', Mandatory)]
  [string]$InventoryPath,

  [Parameter(ParameterSetName='Lookup')]
  [string[]]$LookupValue,

  [Parameter(ParameterSetName='Lookup')]
  [ValidateSet('Any','IP','MAC','Serial','HostName','DeviceName')]
  [string]$LookupBy = 'Any',

  [string]$OutHtml,

  [string[]]$Communities = @('public','private','northwell','netadmin')
)

$ErrorActionPreference = 'SilentlyContinue'
function Get-ExternalCommandPath {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { return $null }
    if ($cmd.PSObject.Properties['Source']) { return [string]$cmd.Source }
    if ($cmd.PSObject.Properties['Path']) { return [string]$cmd.Path }
    return $null
}
$snmpget = Get-ExternalCommandPath 'snmpget.exe'
$snmpwalk = Get-ExternalCommandPath 'snmpwalk.exe'
$oids = @{
  SysName    = '1.3.6.1.2.1.1.5.0'
  SysDescr   = '1.3.6.1.2.1.1.1.0'
  SysObjectID= '1.3.6.1.2.1.1.2.0'
  Serial     = '1.3.6.1.2.1.47.1.1.1.1.11.1'
  Model      = '1.3.6.1.2.1.47.1.1.1.1.13.1'
  DeviceName = '1.3.6.1.2.1.47.1.1.1.1.7.1'
  IfPhys     = '1.3.6.1.2.1.2.2.1.6'
}

function Normalize-Mac {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  $hex = ($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
  if ($hex.Length -lt 12) { return $null }
  (($hex.Substring(0,12) -split '([0-9A-F]{2})' | Where-Object { $_ }) -join ':')
}

function Get-FirstValue {
  param([object[]]$Values)
  foreach ($value in $Values) {
    if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return [string]$value }
  }
  return $null
}

function Parse-SNMPValue {
  param([string]$Line)
  if ($Line -match 'STRING:\s*"([^"]+)"') { return $Matches[1] }
  if ($Line -match 'Hex-STRING:\s*([0-9A-Fa-f\s:]+)') { return ($Matches[1] -replace '\s','') }
  if ($Line -match '=\s*OID:\s*([^\r\n]+)$') { return $Matches[1].Trim() }
  if ($Line -match '=\s*INTEGER:\s*([^\r\n]+)$') { return $Matches[1].Trim() }
  if ($Line -match '=\s*([^\r\n]+)$') { return $Matches[1].Trim(' "') }
  return $null
}

function Try-SNMPGet {
  param([string]$IP,[string]$Oid,[string[]]$CommunityList)
  if (-not $snmpget) { return $null }
  foreach ($community in $CommunityList) {
    foreach ($version in @('2c','1')) {
      $out = & $snmpget -v $version -c $community -t 1 -r 0 $IP $Oid 2>$null
      if ($LASTEXITCODE -eq 0 -and $out) {
        return @{ Value = ($out -join [Environment]::NewLine); Community = $community; Version = $version }
      }
    }
  }
  return $null
}

function Try-SNMPMac {
  param([string]$IP,[string[]]$CommunityList)
  if ($snmpwalk) {
    foreach ($community in $CommunityList) {
      foreach ($version in @('2c','1')) {
        $out = & $snmpwalk -v $version -c $community -t 1 -r 0 -On $IP $oids.IfPhys 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) {
          foreach ($line in ($out -split "`r?`n")) {
            $candidate = Normalize-Mac (Parse-SNMPValue $line)
            if ($candidate -and $candidate -notmatch '^00(:00){5}$') {
              return @{ MAC = $candidate; Source = "SNMP ifPhysAddress ($community/v$version)" }
            }
          }
        }
      }
    }
  }

  for ($index = 1; $index -le 6; $index++) {
    $res = Try-SNMPGet -IP $IP -Oid "$($oids.IfPhys).$index" -CommunityList $CommunityList
    if ($res) {
      $candidate = Normalize-Mac (Parse-SNMPValue $res.Value)
      if ($candidate -and $candidate -notmatch '^00(:00){5}$') {
        return @{ MAC = $candidate; Source = "SNMP ifPhysAddress.$index ($($res.Community)/v$($res.Version))" }
      }
    }
  }

  return $null
}

function Resolve-TargetIPs {
  param([string]$Target)
  if ($Target -match '^\d{1,3}(\.\d{1,3}){3}$') { return @($Target) }
  try {
    [System.Net.Dns]::GetHostAddresses($Target) |
      Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
      ForEach-Object { $_.IPAddressToString } |
      Sort-Object -Unique
  } catch {
    @()
  }
}

function Resolve-ReverseDns {
  param([string]$IP)
  try { ([System.Net.Dns]::GetHostEntry($IP)).HostName } catch { $null }
}

function Test-ClockReachable {
  param([string]$Target)
  try { Test-Connection -ComputerName $Target -Count 1 -Quiet -ErrorAction SilentlyContinue } catch { $false }
}

function Try-ArpMac {
  param([string]$IP)
  try {
    $out = (arp -a $IP) 2>$null
    $m = [regex]::Match(($out -join [Environment]::NewLine), '(?i)\b([0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b')
    if ($m.Success) { return @{ MAC = (Normalize-Mac $m.Value); Source = 'ARP cache' } }
  } catch { }
  return $null
}

function Try-HttpIdentity {
  param([string]$IP)
  try { $resp = Invoke-WebRequest -Uri "http://$IP" -UseBasicParsing -TimeoutSec 3 } catch { return $null }
  $content = [string]$resp.Content
  $server = [string]$resp.Headers['Server']
  $title = [regex]::Match($content, '(?is)<title>(.*?)</title>').Groups[1].Value.Trim()
  $patterns = @{
    DeviceName = '(?i)\b(?:Host\s*Name|Hostname|Device\s*Name|Terminal\s*Name)\b[^A-Za-z0-9]{0,10}([A-Za-z0-9._\-]{3,})'
    Serial     = '(?i)\b(?:Serial(?:\s*Number|\s*No\.?|\s*#)?|S/N)\b[^A-Za-z0-9]{0,10}([A-Za-z0-9._\-/]{4,})'
    Model      = '(?i)\b(?:Model|Platform)\b[^A-Za-z0-9]{0,10}([A-Za-z0-9._\- ]{3,})'
    Firmware   = '(?i)\b(?:Firmware|Software\s*Version|Version)\b[^A-Za-z0-9]{0,10}([A-Za-z0-9._\-/ ]{3,})'
    DeviceID   = '(?i)\b(?:Device\s*ID|Terminal\s*ID)\b[^A-Za-z0-9]{0,10}([A-Za-z0-9._\-/]{3,})'
    MACAddress = '(?i)\b(?:MAC|MAC\s*Address)\b[^A-F0-9]{0,20}([A-F0-9]{2}(?:[:-][A-F0-9]{2}){5}|[A-F0-9]{12})'
  }

  $result = @{
    Title = $title
    Server = $server
    Source = "HTTP http://$IP"
  }

  foreach ($key in $patterns.Keys) {
    $match = [regex]::Match($content, $patterns[$key])
    if ($match.Success) { $result[$key] = $match.Groups[1].Value.Trim() }
  }
  if ($result.MACAddress) { $result.MACAddress = Normalize-Mac $result.MACAddress }

  if ($result.Count -gt 3) { return [pscustomobject]$result }
  return $null
}

function Get-SNMPIdentity {
  param([string]$IP,[string[]]$CommunityList)
  $data = @{}
  foreach ($key in 'SysName','SysDescr','SysObjectID','Serial','Model','DeviceName') {
    $res = Try-SNMPGet -IP $IP -Oid $oids[$key] -CommunityList $CommunityList
    if ($res) {
      $value = Parse-SNMPValue $res.Value
      if ($value) {
        $data[$key] = $value
        $data["${key}Source"] = "SNMP $key ($($res.Community)/v$($res.Version))"
      }
    }
  }
  $mac = Try-SNMPMac -IP $IP -CommunityList $CommunityList
  if ($mac) {
    $data.MACAddress = $mac.MAC
    $data.MACSource = $mac.Source
  }
  if ($data.Count) { return [pscustomobject]$data }
  return $null
}

function Resolve-Manufacturer {
  param([string[]]$Hints)
  $text = (($Hints | Where-Object { $_ }) -join ' ')
  if ($text -match '(?i)\b(?:kronos|ukg)\b') { return 'Kronos/UKG' }
  if ($text -match '(?i)\bzebra\b') { return 'Zebra' }
  if ($text -match '(?i)\bhp\b|hewlett') { return 'HP' }
  if ($text -match '(?i)\bcisco\b') { return 'Cisco' }
  return $null
}

function Get-ProbeTargets {
  if ($Targets -and $Targets.Count) {
    return @($Targets | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
  }
  if ($ListPath -and (Test-Path -LiteralPath $ListPath)) {
    return @(Get-Content -LiteralPath $ListPath | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
  }
  throw 'Provide -Targets or -ListPath when probing live clocks.'
}

function Test-InventoryMatch {
  param([psobject]$Row,[string]$By,[string]$Needle)
  $needleText = if ($By -eq 'MAC') { Normalize-Mac $Needle } else { $Needle.Trim().ToUpperInvariant() }
  $fields = switch ($By) {
    'IP'        { @('IPAddress','IP') }
    'MAC'       { @('MACAddress','MAC') }
    'Serial'    { @('SerialNumber','Serial') }
    'HostName'  { @('HostName','ReverseDns','SysName') }
    'DeviceName'{ @('DeviceName','QueryInput','Title') }
    default     { @('IPAddress','IP','MACAddress','MAC','SerialNumber','Serial','HostName','ReverseDns','DeviceName','QueryInput','Title','SysName') }
  }

  foreach ($field in $fields) {
    $prop = $Row.PSObject.Properties[$field]
    if (-not $prop -or [string]::IsNullOrWhiteSpace([string]$prop.Value)) { continue }
    $value = if ($By -eq 'MAC') { Normalize-Mac $prop.Value } else { ([string]$prop.Value).Trim().ToUpperInvariant() }
    if ($value -and $value -eq $needleText) { return $true }
  }
  return $false
}

if ($PSCmdlet.ParameterSetName -eq 'Lookup') {
  if (-not (Test-Path -LiteralPath $InventoryPath)) { throw "Inventory file not found: $InventoryPath" }
  $inventory = @(Import-Csv -LiteralPath $InventoryPath)
  $results = if ($LookupValue) {
    foreach ($value in $LookupValue) {
      $inventory | Where-Object { Test-InventoryMatch -Row $_ -By $LookupBy -Needle $value }
    }
  } else {
    $inventory
  }
  $results = @($results | Sort-Object IPAddress,HostName,DeviceName -Unique)
  if ($results.Count) {
    $results | Format-Table QueryInput,IPAddress,HostName,DeviceName,MACAddress,SerialNumber,Model -AutoSize | Out-Host
  } else {
    Write-Warning 'No matching inventory rows found.'
  }
  $suiteHtmlHelper = Join-Path $PSScriptRoot '..\tools\ConvertTo-SuiteHtml.ps1'
  if (Test-Path -LiteralPath $suiteHtmlHelper) {
    . $suiteHtmlHelper
    $lookupHtml = if ($OutHtml) {
      $OutHtml
    } else {
      $lookupDir = Split-Path -Parent $InventoryPath
      Join-Path $lookupDir ("KronosClockLookup_{0}.html" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    }
    $results | Select-Object QueryInput,IPAddress,HostName,DeviceName,MACAddress,SerialNumber,Model,Manufacturer,Reachable,Notes |
      ConvertTo-Html -Fragment -PreContent '<h2>Kronos Clock Lookup Results</h2>' |
      ConvertTo-SuiteHtml -Title 'Kronos Clock Lookup' -Subtitle "$($results.Count) matching row(s)" -OutputPath $lookupHtml
    Write-Host "Saved HTML: $lookupHtml" -ForegroundColor Green
  }
  return $results
}

$results = foreach ($target in (Get-ProbeTargets)) {
  $ips = @(Resolve-TargetIPs -Target $target)
  if (-not $ips.Count) {
    [pscustomobject]@{
      QueryInput    = $target
      Reachable     = $false
      IPAddress     = $null
      ReverseDns    = $null
      HostName      = $target
      DeviceName    = $null
      MACAddress    = $null
      SerialNumber  = $null
      Model         = $null
      Manufacturer  = $null
      Firmware      = $null
      SysName       = $null
      SysDescr      = $null
      SysObjectID   = $null
      DeviceID      = $null
      Source        = 'Resolution'
      Notes         = 'Could not resolve target to an IPv4 address.'
    }
    continue
  }

  foreach ($ip in $ips) {
    $reachable = Test-ClockReachable -Target $ip
    $reverseDns = Resolve-ReverseDns -IP $ip
    $sources = New-Object System.Collections.Generic.List[string]
    $notes = New-Object System.Collections.Generic.List[string]
    $snmp = $null
    $http = $null
    $arp = $null

    if ($reachable) {
      $snmp = Get-SNMPIdentity -IP $ip -CommunityList $Communities
      $http = Try-HttpIdentity -IP $ip
      $arp = Try-ArpMac -IP $ip
    } else {
      $notes.Add('Clock did not respond to ICMP at probe time.')
    }

    if ($snmp) {
      foreach ($key in 'SysNameSource','SysDescrSource','SysObjectIDSource','SerialSource','ModelSource','DeviceNameSource','MACSource') {
        if ($snmp.PSObject.Properties[$key] -and $snmp.$key) { $sources.Add([string]$snmp.$key) }
      }
    } elseif (-not $snmpget -and -not $snmpwalk) {
      $notes.Add('Net-SNMP tools not found; SNMP identity probes were skipped.')
    }
    if ($http) { $sources.Add($http.Source) }
    if ($arp) { $sources.Add($arp.Source) }

    $hostName = Get-FirstValue @($reverseDns, $(if ($target -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { $target }), $snmp.SysName)
    $deviceName = Get-FirstValue @($snmp.DeviceName, $http.DeviceName, $snmp.SysName, $hostName)
    $macAddress = Get-FirstValue @($snmp.MACAddress, $http.MACAddress, $arp.MAC)
    $serialNumber = Get-FirstValue @($snmp.Serial, $http.Serial)
    $model = Get-FirstValue @($snmp.Model, $http.Model, $http.Title)
    $firmware = Get-FirstValue @($http.Firmware)
    $deviceId = Get-FirstValue @($http.DeviceID, $snmp.SysObjectID)
    $manufacturer = Resolve-Manufacturer -Hints @($snmp.SysDescr, $model, $http.Server, $http.Title)

    if (-not $macAddress) { $notes.Add('MAC address unavailable.') }
    if (-not $serialNumber) { $notes.Add('Serial number unavailable.') }
    if (-not $model) { $notes.Add('Model unavailable.') }

    [pscustomobject]@{
      QueryInput    = $target
      Reachable     = [bool]$reachable
      IPAddress     = $ip
      ReverseDns    = $reverseDns
      HostName      = $hostName
      DeviceName    = $deviceName
      MACAddress    = $macAddress
      SerialNumber  = $serialNumber
      Model         = $model
      Manufacturer  = $manufacturer
      Firmware      = $firmware
      SysName       = $snmp.SysName
      SysDescr      = $snmp.SysDescr
      SysObjectID   = $snmp.SysObjectID
      DeviceID      = $deviceId
      Source        = (($sources | Where-Object { $_ }) -join ' | ')
      Notes         = (($notes | Where-Object { $_ }) -join '; ')
    }
  }
}

$results = @($results | Sort-Object IPAddress,HostName,DeviceName -Unique)
$results | Format-Table QueryInput,IPAddress,HostName,DeviceName,MACAddress,SerialNumber,Model,Reachable -AutoSize | Out-Host
$parent = Split-Path -Parent $OutCsv
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$results | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
Write-Host "Saved: $OutCsv" -ForegroundColor Green

# ── HTML output ─────────────────────────────────────────────────────
$suiteHtmlHelper = Join-Path $PSScriptRoot '..\tools\ConvertTo-SuiteHtml.ps1'
if (Test-Path -LiteralPath $suiteHtmlHelper) {
  . $suiteHtmlHelper
  $htmlPath = [IO.Path]::ChangeExtension($OutCsv, '.html')
  $results | Select-Object QueryInput,IPAddress,HostName,DeviceName,MACAddress,SerialNumber,Model,Manufacturer,Reachable,Notes |
    ConvertTo-Html -Fragment -PreContent '<h2>Kronos Clock Inventory</h2>' |
    ConvertTo-SuiteHtml -Title 'Kronos Clock Info' -Subtitle "$($results.Count) target(s)" -OutputPath $htmlPath
}

$results