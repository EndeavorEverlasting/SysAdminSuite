param(
  [Parameter(Mandatory)][string]$CsvPath
)

if (-not (Test-Path -LiteralPath $CsvPath)) {
  throw "CSV file not found: $CsvPath"
}

function Get-NativeToolPath {
  param([Parameter(Mandatory)][string]$ToolName)

  $cmd = Get-Command $ToolName -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  if ($ToolName -ieq 'wmic.exe') {
    $knownPaths = @(
      (Join-Path $env:WINDIR 'System32\wbem\WMIC.exe'),
      (Join-Path $env:WINDIR 'SysWOW64\wbem\WMIC.exe')
    )
    foreach ($p in $knownPaths) {
      if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
  }

  return $null
}

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$Arguments = @()
  )

  $lines = @()
  $exitCode = $null
  $thrown = ''
  try {
    $lines = & $FilePath @Arguments 2>&1 | ForEach-Object { "$($_)" }
    $exitCode = $LASTEXITCODE
  } catch {
    $thrown = $_.Exception.Message
    $lines += $thrown
  }

  [pscustomobject]@{
    ExitCode = $exitCode
    Output   = @($lines)
    Text     = ((@($lines) | Where-Object { $_ }) -join ' | ')
    Error    = $thrown
  }
}

function Test-UsableIdentityValue {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  $v = $Value.Trim().ToLowerInvariant()
  $badValues = @('0','00000000','unknown','none','n/a','na','null','default string','system serial number','to be filled by o.e.m.','to be filled by oem','not specified','error','offline')
  return ($badValues -notcontains $v)
}

function ConvertTo-StandardMac {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  if ($Value -match '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}') {
    return ($matches[0].ToUpperInvariant() -replace '-', ':')
  }
  return $null
}

function Get-MacAddressesFromText {
  param([string[]]$Lines)
  $macs = @()
  foreach ($line in @($Lines)) {
    foreach ($match in [regex]::Matches($line, '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}')) {
      $mac = ConvertTo-StandardMac -Value $match.Value
      if ($mac) { $macs += $mac }
    }
  }
  $macs | Sort-Object -Unique
}

function Get-WmicValues {
  param(
    [Parameter(Mandatory)][object]$Probe,
    [Parameter(Mandatory)][string]$Key
  )

  $values = @()
  foreach ($line in @($Probe.Output)) {
    if ($line -match ("^\s*" + [regex]::Escape($Key) + "\s*=\s*(.*?)\s*$")) {
      $value = $matches[1].Trim()
      if ($value) { $values += $value }
    }
  }
  $values
}

function Resolve-HostnameLastResortIp {
  param([Parameter(Mandatory)][string]$HostName)

  $pingPath = Get-NativeToolPath -ToolName 'ping.exe'
  if ($pingPath) {
    $ping = Invoke-NativeCommand -FilePath $pingPath -Arguments @('-4','-n','1', $HostName)
    foreach ($line in $ping.Output) {
      if ($line -match '\[(\d{1,3}(?:\.\d{1,3}){3})\]') { return $matches[1] }
      if ($line -match 'Reply from\s+(\d{1,3}(?:\.\d{1,3}){3})') { return $matches[1] }
    }
  }

  $nslookupPath = Get-NativeToolPath -ToolName 'nslookup.exe'
  if ($nslookupPath) {
    $ns = Invoke-NativeCommand -FilePath $nslookupPath -Arguments @($HostName)
    $foundAddressSection = $false
    foreach ($line in $ns.Output) {
      if ($line -match '^Name:\s+') { $foundAddressSection = $true; continue }
      if ($foundAddressSection -and $line -match 'Address(?:es)?:\s*(\d{1,3}(?:\.\d{1,3}){3})') { return $matches[1] }
      if ($foundAddressSection -and $line -match '^\s*(\d{1,3}(?:\.\d{1,3}){3})\s*$') { return $matches[1] }
    }
  }

  return ''
}

function Try-GetSerialByTarget {
  param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$WmicPath
  )

  if (-not $WmicPath) { return [pscustomobject]@{ Serial = ''; Source = ''; Error = 'wmic.exe unavailable' } }

  $bios = Invoke-NativeCommand -FilePath $WmicPath -Arguments @("/node:$Target", 'bios', 'get', 'SerialNumber', '/value')
  $serials = @(Get-WmicValues -Probe $bios -Key 'SerialNumber' | Where-Object { Test-UsableIdentityValue $_ })
  if ($serials.Count -gt 0) {
    return [pscustomobject]@{ Serial = $serials[0]; Source = "last-resort-ip:wmic BIOS via $Target"; Error = '' }
  }

  $product = Invoke-NativeCommand -FilePath $WmicPath -Arguments @("/node:$Target", 'csproduct', 'get', 'IdentifyingNumber', '/value')
  $serials = @(Get-WmicValues -Probe $product -Key 'IdentifyingNumber' | Where-Object { Test-UsableIdentityValue $_ })
  if ($serials.Count -gt 0) {
    return [pscustomobject]@{ Serial = $serials[0]; Source = "last-resort-ip:wmic CSProduct via $Target"; Error = '' }
  }

  return [pscustomobject]@{ Serial = ''; Source = ''; Error = "No serial returned by WMIC for $Target. BIOS: $($bios.Text) CSProduct: $($product.Text)" }
}

function Try-GetMacByTarget {
  param(
    [Parameter(Mandatory)][string]$Target,
    [string]$WmicPath,
    [string]$NbtstatPath,
    [string]$GetmacPath,
    [string]$ArpPath,
    [switch]$TargetIsIp
  )

  $macs = @()
  $sources = @()
  $errors = @()

  if ($WmicPath) {
    $nic = Invoke-NativeCommand -FilePath $WmicPath -Arguments @("/node:$Target", 'nicconfig', 'where', 'IPEnabled=TRUE', 'get', 'MACAddress', '/value')
    $found = @(Get-WmicValues -Probe $nic -Key 'MACAddress' | ForEach-Object { ConvertTo-StandardMac $_ } | Where-Object { $_ })
    if ($found.Count -gt 0) { $macs += $found; $sources += "last-resort-ip:wmic NICConfig via $Target" }
    else { $errors += "WMIC MAC failed for $Target: $($nic.Text)" }
  }

  if ($NbtstatPath) {
    $args = if ($TargetIsIp) { @('-A', $Target) } else { @('-a', $Target) }
    $nbt = Invoke-NativeCommand -FilePath $NbtstatPath -Arguments $args
    $found = @(Get-MacAddressesFromText -Lines $nbt.Output)
    if ($found.Count -gt 0) { $macs += $found; $sources += "last-resort-ip:nbtstat via $Target" }
    else { $errors += "NBTSTAT MAC failed for $Target: $($nbt.Text)" }
  }

  if ($GetmacPath) {
    $gm = Invoke-NativeCommand -FilePath $GetmacPath -Arguments @('/s', $Target, '/fo', 'csv', '/nh')
    $found = @(Get-MacAddressesFromText -Lines $gm.Output)
    if ($found.Count -gt 0) { $macs += $found; $sources += "last-resort-ip:getmac via $Target" }
    else { $errors += "GETMAC failed for $Target: $($gm.Text)" }
  }

  if ($TargetIsIp -and $ArpPath) {
    $arp = Invoke-NativeCommand -FilePath $ArpPath -Arguments @('-a', $Target)
    $found = @(Get-MacAddressesFromText -Lines $arp.Output)
    if ($found.Count -gt 0) { $macs += $found; $sources += "last-resort-ip:arp via $Target" }
    else { $errors += "ARP failed for $Target: $($arp.Text)" }
  }

  [pscustomobject]@{
    MACAddress = (($macs | Sort-Object -Unique) -join ';')
    Source     = (($sources | Sort-Object -Unique) -join ';')
    Error      = (($errors | Where-Object { $_ }) -join ' || ')
  }
}

$rows = @(Import-Csv -LiteralPath $CsvPath)
$wmicPath = Get-NativeToolPath -ToolName 'wmic.exe'
$nbtstatPath = Get-NativeToolPath -ToolName 'nbtstat.exe'
$getmacPath = Get-NativeToolPath -ToolName 'getmac.exe'
$arpPath = Get-NativeToolPath -ToolName 'arp.exe'

Write-Host "[REPAIR] Last-resort IP repair starting for $($rows.Count) row(s)." -ForegroundColor Cyan
Write-Host "[REPAIR] Rule: hostname evidence stays primary; IP is only used when serial or MAC is missing." -ForegroundColor Yellow
if (-not $wmicPath) { Write-Warning '[REPAIR] wmic.exe is unavailable. IP fallback may recover MAC, but cannot recover BIOS serial without a WMIC/WMI-capable path.' }

$total = $rows.Count
$index = 0
foreach ($row in $rows) {
  $index++
  $hostName = $row.HostName
  $needsSerial = -not (Test-UsableIdentityValue $row.Serial)
  $needsMac = -not (Test-UsableIdentityValue $row.MACAddress)

  if (-not $needsSerial -and -not $needsMac) { continue }

  Write-Progress -Activity 'Repair partial MachineInfo identity' -Status "[$index/$total] $hostName" -PercentComplete ([int](($index / [Math]::Max($total,1)) * 100))
  Write-Host "[REPAIR][$index/$total] $hostName needs: Serial=$needsSerial MAC=$needsMac" -ForegroundColor Cyan

  $actions = @()
  $repairErrors = @()

  $lastIp = Resolve-HostnameLastResortIp -HostName $hostName
  if ($lastIp) {
    $actions += "Resolved last-resort IP $lastIp from hostname"
    if ($row.PSObject.Properties.Name -notcontains 'LastResortIPAddress') { $row | Add-Member -NotePropertyName LastResortIPAddress -NotePropertyValue '' }
    if ($row.PSObject.Properties.Name -notcontains 'IPFallbackSource') { $row | Add-Member -NotePropertyName IPFallbackSource -NotePropertyValue '' }
    $row.LastResortIPAddress = $lastIp
    $row.IPFallbackSource = 'ping/nslookup last-resort only'
  } else {
    $repairErrors += 'Could not resolve a last-resort IP from hostname'
  }

  if ($needsSerial) {
    $serialTargets = @($hostName)
    if ($lastIp) { $serialTargets += $lastIp }
    foreach ($target in $serialTargets | Select-Object -Unique) {
      $serialProbe = Try-GetSerialByTarget -Target $target -WmicPath $wmicPath
      if (Test-UsableIdentityValue $serialProbe.Serial) {
        $row.Serial = $serialProbe.Serial
        $row.SerialSource = $serialProbe.Source
        $actions += "Recovered serial via $target"
        break
      } elseif ($serialProbe.Error) {
        $repairErrors += $serialProbe.Error
      }
    }
  }

  if ($needsMac) {
    $macTargets = @([pscustomobject]@{ Value = $hostName; IsIp = $false })
    if ($lastIp) { $macTargets += [pscustomobject]@{ Value = $lastIp; IsIp = $true } }
    foreach ($target in $macTargets) {
      $macProbe = Try-GetMacByTarget -Target $target.Value -WmicPath $wmicPath -NbtstatPath $nbtstatPath -GetmacPath $getmacPath -ArpPath $arpPath -TargetIsIp:([bool]$target.IsIp)
      if (Test-UsableIdentityValue $macProbe.MACAddress) {
        $row.MACAddress = $macProbe.MACAddress
        $row.MACSource = $macProbe.Source
        $actions += "Recovered MAC via $($target.Value)"
        break
      } elseif ($macProbe.Error) {
        $repairErrors += $macProbe.Error
      }
    }
  }

  $serialOk = Test-UsableIdentityValue $row.Serial
  $macOk = Test-UsableIdentityValue $row.MACAddress
  if ($serialOk -and $macOk) {
    $row.Status = 'OK'
    $row.ErrorCategory = ''
    $actions += 'Full serial+MAC identity recovered after last-resort repair'
  } elseif ($serialOk -or $macOk) {
    $row.Status = 'Partial Identity'
    if (-not $row.ErrorCategory) { $row.ErrorCategory = 'LAST_RESORT_PARTIAL_IDENTITY' }
  } else {
    $row.Status = 'Query Failed'
    if (-not $row.ErrorCategory) { $row.ErrorCategory = 'LAST_RESORT_IDENTITY_FAILED' }
  }

  if ($row.PSObject.Properties.Name -notcontains 'RepairActions') { $row | Add-Member -NotePropertyName RepairActions -NotePropertyValue '' }
  if ($row.PSObject.Properties.Name -notcontains 'RepairErrors') { $row | Add-Member -NotePropertyName RepairErrors -NotePropertyValue '' }
  $row.RepairActions = ($actions -join ' || ')
  $row.RepairErrors = (($repairErrors | Where-Object { $_ }) -join ' || ')

  if (-not $serialOk -or -not $macOk) {
    $missing = @()
    if (-not $serialOk) { $missing += 'Serial still missing' }
    if (-not $macOk) { $missing += 'MAC still missing' }
    $row.FailureReason = (($missing + @($row.FailureReason) + @($row.RepairActions)) | Where-Object { $_ }) -join ' '
  } else {
    $row.FailureReason = "Full identity recovered. $($row.RepairActions)"
  }
}
Write-Progress -Activity 'Repair partial MachineInfo identity' -Completed

$rows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation
Write-Host "[REPAIR] Last-resort repair complete. CSV updated: $CsvPath" -ForegroundColor Green
