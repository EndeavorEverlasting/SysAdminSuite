param(
  [Parameter(Mandatory)][string]$CsvPath,
  [int]$CheckpointEvery = 10,
  [switch]$DeepSerialRepair
)

if (-not (Test-Path -LiteralPath $CsvPath)) { throw "CSV file not found: $CsvPath" }

$script:Rows = @()
$script:LogPath = [IO.Path]::ChangeExtension($CsvPath, '.repair.log')
$script:HtmlHelper = Join-Path $PSScriptRoot 'Update-MachineInfoHostnameHtml.ps1'

function Write-RepairLog {
  param([string]$Message, [string]$Level = 'INFO')
  $line = "{0} [{1}] {2}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
  Add-Content -LiteralPath $script:LogPath -Value $line
  if ($Level -eq 'WARN') { Write-Warning $Message }
  elseif ($Level -eq 'ERROR') { Write-Host "[REPAIR][ERROR] $Message" -ForegroundColor Red }
  else { Write-Host "[REPAIR] $Message" -ForegroundColor Cyan }
}

function Save-RepairCheckpoint {
  param([string]$Reason = 'checkpoint')
  if ($script:Rows -and $script:Rows.Count -gt 0) {
    $script:Rows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation
    Write-RepairLog "Saved $Reason to $CsvPath"
    if (Test-Path -LiteralPath $script:HtmlHelper) {
      try { & $script:HtmlHelper -CsvPath $CsvPath | Out-Null; Write-RepairLog "Refreshed HTML after $Reason" }
      catch { Write-RepairLog "HTML refresh failed during $Reason`: $($_.Exception.Message)" 'WARN' }
    }
  }
}

trap {
  Write-RepairLog "Repair interrupted or failed. Saving completed work before exit. Error: $($_.Exception.Message)" 'ERROR'
  Save-RepairCheckpoint -Reason 'interrupted repair checkpoint'
  break
}

function Get-NativeToolPath {
  param([Parameter(Mandatory)][string]$ToolName)
  $cmd = Get-Command $ToolName -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  if ($ToolName -ieq 'wmic.exe') {
    foreach ($p in @((Join-Path $env:WINDIR 'System32\wbem\WMIC.exe'), (Join-Path $env:WINDIR 'SysWOW64\wbem\WMIC.exe'))) {
      if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
  }
  return $null
}

function Invoke-NativeCommand {
  param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @())
  $lines = @(); $exitCode = $null; $thrown = ''
  try { $lines = & $FilePath @Arguments 2>&1 | ForEach-Object { "$($_)" }; $exitCode = $LASTEXITCODE }
  catch { $thrown = $_.Exception.Message; $lines += $thrown }
  [pscustomobject]@{ ExitCode = $exitCode; Output = @($lines); Text = ((@($lines) | Where-Object { $_ }) -join ' | '); Error = $thrown }
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
  if ($Value -match '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}') { return ($matches[0].ToUpperInvariant() -replace '-', ':') }
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
  param([Parameter(Mandatory)][object]$Probe, [Parameter(Mandatory)][string]$Key)
  $values = @()
  foreach ($line in @($Probe.Output)) {
    if ($line -match ("^\s*" + [regex]::Escape($Key) + "\s*=\s*(.*?)\s*$")) {
      $value = $matches[1].Trim(); if ($value) { $values += $value }
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

function Try-GetSerialByPowerShellWmi {
  param([Parameter(Mandatory)][string]$Target)
  if (-not $DeepSerialRepair) {
    return [pscustomobject]@{ Serial = ''; Source = ''; Error = 'Deep PowerShell CIM/WMI serial repair skipped for speed. Use -DeepSerialRepair to try it.' }
  }
  try {
    $sessionOption = New-CimSessionOption -Protocol Dcom
    $session = New-CimSession -ComputerName $Target -SessionOption $sessionOption -OperationTimeoutSec 6 -ErrorAction Stop
    try {
      $bios = Get-CimInstance -CimSession $session -ClassName Win32_BIOS -OperationTimeoutSec 6 -ErrorAction Stop
      if ($bios -and (Test-UsableIdentityValue $bios.SerialNumber)) {
        return [pscustomobject]@{ Serial = $bios.SerialNumber; Source = "last-resort:PowerShell CIM Win32_BIOS via $Target"; Error = '' }
      }
    } finally { if ($session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue } }
  } catch { return [pscustomobject]@{ Serial = ''; Source = ''; Error = "CIM serial failed fast for ${Target}: $($_.Exception.Message)" } }
  [pscustomobject]@{ Serial = ''; Source = ''; Error = "CIM serial returned blank for ${Target}" }
}

function Try-GetSerialByTarget {
  param([Parameter(Mandatory)][string]$Target, [string]$WmicPath)
  $errors = @()
  if ($WmicPath) {
    $bios = Invoke-NativeCommand -FilePath $WmicPath -Arguments @("/node:$Target", 'bios', 'get', 'SerialNumber', '/value')
    $serials = @(Get-WmicValues -Probe $bios -Key 'SerialNumber' | Where-Object { Test-UsableIdentityValue $_ })
    if ($serials.Count -gt 0) { return [pscustomobject]@{ Serial = $serials[0]; Source = "last-resort:wmic BIOS via $Target"; Error = '' } }
    $errors += "WMIC BIOS serial failed for ${Target}: $($bios.Text)"
    $product = Invoke-NativeCommand -FilePath $WmicPath -Arguments @("/node:$Target", 'csproduct', 'get', 'IdentifyingNumber', '/value')
    $serials = @(Get-WmicValues -Probe $product -Key 'IdentifyingNumber' | Where-Object { Test-UsableIdentityValue $_ })
    if ($serials.Count -gt 0) { return [pscustomobject]@{ Serial = $serials[0]; Source = "last-resort:wmic CSProduct via $Target"; Error = '' } }
    $errors += "WMIC CSProduct serial failed for ${Target}: $($product.Text)"
  } else { $errors += 'wmic.exe unavailable' }
  $psProbe = Try-GetSerialByPowerShellWmi -Target $Target
  if (Test-UsableIdentityValue $psProbe.Serial) { return $psProbe }
  if ($psProbe.Error) { $errors += $psProbe.Error }
  return [pscustomobject]@{ Serial = ''; Source = ''; Error = ($errors -join ' || ') }
}

function Try-GetMacByTarget {
  param([Parameter(Mandatory)][string]$Target, [string]$WmicPath, [string]$NbtstatPath, [string]$GetmacPath, [string]$ArpPath, [switch]$TargetIsIp)
  $macs = @(); $sources = @(); $errors = @()
  if ($WmicPath) {
    $nic = Invoke-NativeCommand -FilePath $WmicPath -Arguments @("/node:$Target", 'nicconfig', 'where', 'IPEnabled=TRUE', 'get', 'MACAddress', '/value')
    $found = @(Get-WmicValues -Probe $nic -Key 'MACAddress' | ForEach-Object { ConvertTo-StandardMac $_ } | Where-Object { $_ })
    if ($found.Count -gt 0) { $macs += $found; $sources += "last-resort:wmic NICConfig via $Target" } else { $errors += "WMIC MAC failed for ${Target}: $($nic.Text)" }
  }
  if ($NbtstatPath) {
    $args = if ($TargetIsIp) { @('-A', $Target) } else { @('-a', $Target) }
    $nbt = Invoke-NativeCommand -FilePath $NbtstatPath -Arguments $args
    $found = @(Get-MacAddressesFromText -Lines $nbt.Output)
    if ($found.Count -gt 0) { $macs += $found; $sources += "last-resort:nbtstat via $Target" } else { $errors += "NBTSTAT MAC failed for ${Target}: $($nbt.Text)" }
  }
  if ($GetmacPath) {
    $gm = Invoke-NativeCommand -FilePath $GetmacPath -Arguments @('/s', $Target, '/fo', 'csv', '/nh')
    $found = @(Get-MacAddressesFromText -Lines $gm.Output)
    if ($found.Count -gt 0) { $macs += $found; $sources += "last-resort:getmac via $Target" } else { $errors += "GETMAC failed for ${Target}: $($gm.Text)" }
  }
  if ($TargetIsIp -and $ArpPath) {
    $arp = Invoke-NativeCommand -FilePath $ArpPath -Arguments @('-a', $Target)
    $found = @(Get-MacAddressesFromText -Lines $arp.Output)
    if ($found.Count -gt 0) { $macs += $found; $sources += "last-resort:arp via $Target" } else { $errors += "ARP failed for ${Target}: $($arp.Text)" }
  }
  [pscustomobject]@{ MACAddress = (($macs | Where-Object { $_ } | Sort-Object -Unique) -join ';'); Source = (($sources | Where-Object { $_ } | Sort-Object -Unique) -join ';'); Error = (($errors | Where-Object { $_ }) -join ' || ') }
}

$script:Rows = @(Import-Csv -LiteralPath $CsvPath)
$repairColumns = @('LastResortIPAddress','IPFallbackSource','RepairActions','RepairErrors')
foreach ($row in $script:Rows) { foreach ($column in $repairColumns) { if ($row.PSObject.Properties.Name -notcontains $column) { $row | Add-Member -NotePropertyName $column -NotePropertyValue '' } } }

$wmicPath = Get-NativeToolPath -ToolName 'wmic.exe'
$nbtstatPath = Get-NativeToolPath -ToolName 'nbtstat.exe'
$getmacPath = Get-NativeToolPath -ToolName 'getmac.exe'
$arpPath = Get-NativeToolPath -ToolName 'arp.exe'

Write-RepairLog "Last-resort repair starting for $($script:Rows.Count) row(s)."
Write-RepairLog "Rule: hostname evidence stays primary; IP is only used when serial or MAC is missing."
Write-RepairLog "Checkpoints save every $CheckpointEvery repaired row(s), so canceling keeps completed CSV/HTML data."
if (-not $wmicPath -and -not $DeepSerialRepair) { Write-RepairLog 'wmic.exe unavailable and DeepSerialRepair is off. Serial repair will be skipped fast; use an inventory source or rerun repair with -DeepSerialRepair.' 'WARN' }

$total = $script:Rows.Count; $index = 0; $repairedSinceCheckpoint = 0
foreach ($row in $script:Rows) {
  $index++; $hostName = $row.HostName
  $needsSerial = -not (Test-UsableIdentityValue $row.Serial)
  $needsMac = -not (Test-UsableIdentityValue $row.MACAddress)
  if (-not $needsSerial -and -not $needsMac) { continue }

  Write-Progress -Activity 'Repair partial MachineInfo identity' -Status "[$index/$total] $hostName" -PercentComplete ([int](($index / [Math]::Max($total,1)) * 100))
  Write-RepairLog "[$index/$total] $hostName needs: Serial=$needsSerial MAC=$needsMac"
  $actions = @(); $repairErrors = @()

  $lastIp = Resolve-HostnameLastResortIp -HostName $hostName
  if ($lastIp) { $actions += "Resolved last-resort IP $lastIp from hostname"; $row.LastResortIPAddress = $lastIp; $row.IPFallbackSource = 'ping/nslookup last-resort only' }
  else { $repairErrors += 'Could not resolve a last-resort IP from hostname' }

  if ($needsSerial) {
    if (-not $wmicPath -and -not $DeepSerialRepair) { $repairErrors += 'Serial repair skipped fast because wmic.exe is unavailable and DeepSerialRepair is off.' }
    else {
      $serialTargets = @($hostName); if ($lastIp) { $serialTargets += $lastIp }
      foreach ($target in $serialTargets | Select-Object -Unique) {
        $serialProbe = Try-GetSerialByTarget -Target $target -WmicPath $wmicPath
        if (Test-UsableIdentityValue $serialProbe.Serial) { $row.Serial = $serialProbe.Serial; $row.SerialSource = $serialProbe.Source; $actions += "Recovered serial via $target"; break }
        elseif ($serialProbe.Error) { $repairErrors += $serialProbe.Error }
      }
    }
  }

  if ($needsMac) {
    $macTargets = @([pscustomobject]@{ Value = $hostName; IsIp = $false }); if ($lastIp) { $macTargets += [pscustomobject]@{ Value = $lastIp; IsIp = $true } }
    foreach ($target in $macTargets) {
      $macProbe = Try-GetMacByTarget -Target $target.Value -WmicPath $wmicPath -NbtstatPath $nbtstatPath -GetmacPath $getmacPath -ArpPath $arpPath -TargetIsIp:([bool]$target.IsIp)
      if (Test-UsableIdentityValue $macProbe.MACAddress) { $row.MACAddress = $macProbe.MACAddress; $row.MACSource = $macProbe.Source; $actions += "Recovered MAC via $($target.Value)"; break }
      elseif ($macProbe.Error) { $repairErrors += $macProbe.Error }
    }
  }

  $serialOk = Test-UsableIdentityValue $row.Serial; $macOk = Test-UsableIdentityValue $row.MACAddress
  if ($serialOk -and $macOk) { $row.Status = 'OK'; $row.ErrorCategory = ''; $actions += 'Full serial+MAC identity recovered after last-resort repair' }
  elseif ($serialOk -or $macOk) { $row.Status = 'Partial Identity'; if (-not $row.ErrorCategory) { $row.ErrorCategory = 'LAST_RESORT_PARTIAL_IDENTITY' } }
  else { $row.Status = 'Query Failed'; if (-not $row.ErrorCategory) { $row.ErrorCategory = 'LAST_RESORT_IDENTITY_FAILED' } }

  $row.RepairActions = ($actions -join ' || ')
  $row.RepairErrors = (($repairErrors | Where-Object { $_ }) -join ' || ')
  if (-not $serialOk -or -not $macOk) {
    $missing = @(); if (-not $serialOk) { $missing += 'Serial still missing' }; if (-not $macOk) { $missing += 'MAC still missing' }
    $row.FailureReason = (($missing + @($row.FailureReason) + @($row.RepairActions)) | Where-Object { $_ }) -join ' '
  } else { $row.FailureReason = "Full identity recovered. $($row.RepairActions)" }

  $repairedSinceCheckpoint++
  if ($CheckpointEvery -gt 0 -and $repairedSinceCheckpoint -ge $CheckpointEvery) { Save-RepairCheckpoint -Reason "repair checkpoint after $index/$total rows"; $repairedSinceCheckpoint = 0 }
}
Write-Progress -Activity 'Repair partial MachineInfo identity' -Completed
Save-RepairCheckpoint -Reason 'final repair output'
Write-RepairLog "Last-resort repair complete. CSV updated: $CsvPath"
