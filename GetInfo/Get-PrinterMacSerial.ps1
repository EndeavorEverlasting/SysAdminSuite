[CmdletBinding()]
param(
  # Provide IPs inline: -IPs 10.202.46.169,10.202.46.168 ...
  [string[]]$IPs,

  # Or a text file with one IP per line
  [string]$ListPath,

  # Where to drop results
  [string]$OutCsv = ".\PrinterProbe.csv",

  # Optional: add or change community strings to try (first winner wins)
  [string[]]$Communities = @('public','private','northwell','zebra','netadmin'),

  # Stop after first success (true) or try all methods (false)
  [bool]$StopOnFirstSuccess = $true,

  # Make this $true if you want to skip web scraping / 9100 probing
  [bool]$SNMPOnly = $false
)

# -------------------------------
# Utilities
# -------------------------------
$ErrorActionPreference = 'SilentlyContinue'
$log = ".\PrinterProbe.log"

function Write-Log {
  param([string]$msg)
  $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
  Add-Content -Path $log -Value $line
  Write-Verbose $line
}

function Test-HostUp {
  param([string]$IP)
  try {
    return Test-Connection -ComputerName $IP -Count 1 -Quiet -ErrorAction SilentlyContinue
  } catch { return $false }
}

function Find-Exe {
  param([string]$name)
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

# Normalize hex to AA:BB:CC:DD:EE:FF
function Normalize-Mac {
  param([string]$raw)
  if (-not $raw) { return $null }
  $hex = ($raw -replace '[^0-9A-Fa-f]', '') # keep hex only
  if ($hex.Length -lt 12) { return $null }
  ($hex.Substring(0,12).ToCharArray() -split '(.{2})' | Where-Object { $_ -ne '' }) -join ':'
}

# -------------------------------
# SNMP helpers (via Net-SNMP if available)
# -------------------------------
$snmpget  = Find-Exe 'snmpget.exe'
$snmpwalk = Find-Exe 'snmpwalk.exe'

# Standard Printer-MIB serial OID
$OID_Serial = '1.3.6.1.2.1.43.5.1.1.17.1'
# ifPhysAddress table (MAC per interface)
$OID_IfPhys = '1.3.6.1.2.1.2.2.1.6'

function Try-SNMPGet {
  param([string]$IP, [string]$oid, [string[]]$communities)
  if (-not $snmpget) { return $null }

  foreach ($comm in $communities) {
    foreach ($ver in @('2c','1')) {
      $out = & $snmpget -v $ver -c $comm -t 1 -r 0 $IP $oid 2>$null
      if ($LASTEXITCODE -eq 0 -and $out) {
        return @{ value = $out; community = $comm; version = $ver }
      }
    }
  }
  return $null
}

function Parse-SNMPValue {
  param([string]$line)
  # Examples:
  # ... = STRING: "ZBR12345"
  # ... = Hex-STRING: 00 11 22 33 44 55
  if ($line -match 'STRING:\s*"([^"]+)"') { return $Matches[1] }
  if ($line -match 'Hex-STRING:\s*([0-9A-Fa-f\s:]+)') {
    return ($Matches[1] -replace '\s','' -replace ':','')
  }
  if ($line -match '=\s*([^\r\n]+)$') { return $Matches[1].Trim() }
  return $null
}

function Try-SNMP-Mac {
  param([string]$IP, [string[]]$communities)
  if (-not $snmpwalk) {
    # Fallback: try a few ifIndex with snmpget
    for ($i=1; $i -le 6; $i++) {
      $res = Try-SNMPGet -IP $IP -oid "$OID_IfPhys.$i" -communities $communities
      if ($res) {
        $val = Normalize-Mac (Parse-SNMPValue $res.value)
        if ($val -and $val -notmatch '^00(?:[:]?00){5}$') {
          return @{ MAC = $val; Source = "SNMP ifPhysAddress.$i ($($res.community)/v$($res.version))" }
        }
      }
    }
    return $null
  }

  foreach ($comm in $communities) {
    foreach ($ver in @('2c','1')) {
      $out = & $snmpwalk -v $ver -c $comm -t 1 -r 0 -On $IP $OID_IfPhys 2>$null
      if ($LASTEXITCODE -eq 0 -and $out) {
        $lines = $out -split "`r?`n" | Where-Object { $_ -match ' = ' }
        foreach ($ln in $lines) {
          $candidate = Normalize-Mac (Parse-SNMPValue $ln)
          if ($candidate -and $candidate -notmatch '^00(?:[:]?00){5}$') {
            return @{ MAC = $candidate; Source = "SNMP ifPhysAddress ($comm/v$ver)" }
          }
        }
      }
    }
  }
  return $null
}

function Try-SNMP-Serial {
  param([string]$IP, [string[]]$communities)
  $res = Try-SNMPGet -IP $IP -oid $OID_Serial -communities $communities
  if (-not $res) { return $null }
  $serial = Parse-SNMPValue $res.value
  if ($serial) { return @{ Serial = $serial; Source = "SNMP prtGeneralSerialNumber ($($res.community)/v$($res.version))" } }
  return $null
}

# -------------------------------
# HTTP scrape (common on Zebra web UI)
# -------------------------------
function Try-HTTP-Scrape {
  param([string]$IP)

  try {
    $resp = Invoke-WebRequest -Uri "http://$IP" -UseBasicParsing -TimeoutSec 3
  } catch {
    return $null
  }
  $html = ($resp.Content | Out-String)

  # MAC patterns
  $macMatch = [regex]::Match($html, '(?i)\b(?:MAC|MAC Address|HWaddr)\b[^A-F0-9]{0,20}([A-F0-9]{2}([:\-])[A-F0-9]{2}(\2[A-F0-9]{2}){4})')
  $mac = $null
  if ($macMatch.Success) { $mac = Normalize-Mac $macMatch.Groups[1].Value }

  # Serial patterns
  $serial = $null
  foreach ($pat in @(
      '(?i)\bSerial(?: Number| No\.?| #)?\b[^A-Za-z0-9]{0,10}([A-Za-z0-9\-_/]{5,})',
      '(?i)\bS/N\b[^A-Za-z0-9]{0,10}([A-Za-z0-9\-_/]{5,})'
  )) {
    $m = [regex]::Match($html, $pat)
    if ($m.Success) { $serial = $m.Groups[1].Value.Trim(); break }
  }

  if ($mac -or $serial) {
    return @{
      MAC    = $mac
      Serial = $serial
      Source = "HTTP scrape of http://$IP"
    }
  }
  return $null
}

# -------------------------------
# Zebra raw port (9100) probe ΓÇö ZPL dump of settings
# -------------------------------
function Try-9100-ZPL {
  param([string]$IP)

  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect($IP, 9100, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne(1500, $false)) { $client.Close(); return $null }
    $client.EndConnect($iar)
    $stream = $client.GetStream()

    # Ask for "Host Config" dump; many Zebra models respond with readable config (contains serial)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("^XA^HH^XZ`r`n")
    $stream.Write($bytes, 0, $bytes.Length)
    Start-Sleep -Milliseconds 400

    $buf = New-Object byte[] 8192
    $ms  = New-Object System.IO.MemoryStream
    while ($stream.DataAvailable) {
      $read = $stream.Read($buf,0,$buf.Length)
      if ($read -le 0) { break }
      $ms.Write($buf,0,$read)
      Start-Sleep -Milliseconds 80
    }
    $client.Close()

    $txt = [System.Text.Encoding]::ASCII.GetString($ms.ToArray())

    if (-not $txt) { return $null }

    $mac = $null
    $serial = $null

    $m1 = [regex]::Match($txt, '(?i)\b(MAC|MAC Address)\b[^A-F0-9]{0,20}([A-F0-9]{12}|[A-F0-9]{2}[:-](?:[A-F0-9]{2}[:-]){4}[A-F0-9]{2})')
    if ($m1.Success) { $mac = Normalize-Mac $m1.Groups[2].Value }

    foreach ($pat in @(
      '(?i)\bSerial(?: Number| #)?\b[^A-Za-z0-9]{0,10}([A-Za-z0-9\-_/]{5,})',
      '(?i)\bZBR?([A-Za-z0-9\-_/]{4,})' # sometimes shows as model+serial
    )) {
      $m = [regex]::Match($txt, $pat)
      if ($m.Success) { $serial = $m.Groups[$m.Groups.Count-1].Value.Trim(); break }
    }

    if ($mac -or $serial) { return @{ MAC=$mac; Serial=$serial; Source="9100 ZPL (^HH)" } }
    return $null
  } catch { return $null }
}

# -------------------------------
# ARP fallback (L2 only, after ping)
# -------------------------------
function Try-ARP {
  param([string]$IP)
  try {
    $out = (arp -a $IP) 2>$null
    if (-not $out) { return $null }
    $m = [regex]::Match($out, '(?i)\b([0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b')
    if ($m.Success) { return @{ MAC = Normalize-Mac $m.Value; Source = "ARP cache" } }
    return $null
  } catch { return $null }
}

# -------------------------------
# Main gatherer
# -------------------------------
function Get-Targets {
  if ($IPs -and $IPs.Count) { return $IPs }
  if ($ListPath -and (Test-Path $ListPath)) {
    return (Get-Content $ListPath | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
  }
  throw "Provide -IPs or -ListPath."
}

$targets = Get-Targets
Write-Log "----- Run start: $($targets -join ', ') -----"

$rows = foreach ($ip in $targets) {
  $status   = 'Unknown'
  $mac      = $null
  $serial   = $null
  $sources  = @()
  $notes    = @()

  $up = Test-HostUp $ip
  $status = if ($up) { 'Online' } else { 'Offline/Unreachable' }
  Write-Log "$ip status: $status"

  if ($up) {
    # 1) SNMP
    $snmpSerial = Try-SNMP-Serial -IP $ip -communities $Communities
    if ($snmpSerial) {
      $serial = $snmpSerial.Serial
      $sources += $snmpSerial.Source
      Write-Log "$ip serial via $($snmpSerial.Source): $serial"
    }

    $snmpMac = Try-SNMP-Mac -IP $ip -communities $Communities
    if ($snmpMac) {
      $mac = $snmpMac.MAC
      $sources += $snmpMac.Source
      Write-Log "$ip MAC via $($snmpMac.Source): $mac"
    }

    if ($StopOnFirstSuccess -and $serial -and $mac) {
      # done
    } elseif (-not $SNMPOnly) {
      # 2) HTTP scrape
      if (-not ($serial -and $mac)) {
        $http = Try-HTTP-Scrape -IP $ip
        if ($http) {
          if (-not $mac -and $http.MAC)    { $mac = $http.MAC }
          if (-not $serial -and $http.Serial) { $serial = $http.Serial }
          if ($http.Source) { $sources += $http.Source }
          Write-Log "$ip HTTP scrape => MAC=$mac, Serial=$serial"
        }
      }

      # 3) 9100 ZPL
      if (-not ($serial -and $mac)) {
        $zpl = Try-9100-ZPL -IP $ip
        if ($zpl) {
          if (-not $mac -and $zpl.MAC)    { $mac = $zpl.MAC }
          if (-not $serial -and $zpl.Serial) { $serial = $zpl.Serial }
          if ($zpl.Source) { $sources += $zpl.Source }
          Write-Log "$ip 9100 ZPL => MAC=$mac, Serial=$serial"
        }
      }

      # 4) ARP last resort (MAC only if same L2)
      if (-not $mac) {
        $arp = Try-ARP -IP $ip
        if ($arp) {
          $mac = $arp.MAC
          $sources += $arp.Source
          Write-Log "$ip ARP => MAC=$mac"
        }
      }
    }
  } else {
    $notes += 'Host unreachable (ICMP). Check VLAN/routing/power.'
  }

  if (-not $snmpget -and -not $snmpwalk) {
    $notes += 'Net-SNMP not found; SNMP methods skipped.'
  }

  if (-not $serial) { $notes += 'Serial unavailable' }
  if (-not $mac)    { $notes += 'MAC unavailable'    }

  [pscustomobject]@{
    IP      = $ip
    Status  = $status
    MAC     = $mac
    Serial  = $serial
    Source  = ($sources -join ' | ')
    Notes   = ($notes -join '; ')
  }
}

$rows | Tee-Object -Variable Results | Format-Table -AutoSize
$Results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutCsv
Write-Log "Wrote CSV: $OutCsv"
Write-Host "`nSaved: $OutCsv"