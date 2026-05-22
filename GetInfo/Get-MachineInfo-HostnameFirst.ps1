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

    # Hostname-first native probe.
    # This copy intentionally does not pre-resolve hostnames to IP addresses,
    # does not export IP addresses, and does not use PowerShell WMI/CIM cmdlets
    # for remote collection. It uses native Windows tools by hostname instead:
    #   - wmic.exe for BIOS serial, system identity, model, and NIC MACs
    #   - nbtstat.exe as a MAC/name fallback
    #   - getmac.exe as a MAC fallback
    #   - nmap.exe, when available, only as a failure-diagnostic probe
    # Serial collection still requires a working remote WMI/RPC path on the target.
    # If the network, firewall, endpoint policy, or permissions block that path,
    # the row reports a specific error category and diagnostic detail.

    $isLocal = $Computer -eq $env:COMPUTERNAME -or
               $Computer -eq 'localhost' -or
               $Computer -eq '127.0.0.1' -or
               $Computer -eq '.'

    function New-MachineInfoRecord {
      param(
        [string]$Status,
        [string]$ErrorCategory = '',
        [string]$ErrorMessage = '',
        [string]$Serial = '',
        [string]$SerialSource = '',
        [string]$MACAddress = '',
        [string]$MACSource = '',
        [string]$ReportedComputerName = '',
        [string]$ReportedNameSource = '',
        [string]$Model = '',
        [string]$Manufacturer = '',
        [string]$IdentityWarning = '',
        [string]$RpcProbe = '',
        [string]$SmbProbe = '',
        [string]$WinRmProbe = '',
        [string]$FallbackProbe = '',
        [string]$ProbeSummary = ''
      )

      [pscustomobject]@{
        Timestamp            = $timestamp
        HostName             = $Computer
        ReportedComputerName = $ReportedComputerName
        Serial               = $Serial
        SerialSource         = $SerialSource
        MACAddress           = $MACAddress
        MACSource            = $MACSource
        Model                = $Model
        Manufacturer         = $Manufacturer
        ReportedNameSource   = $ReportedNameSource
        IdentityWarning      = $IdentityWarning
        RpcProbe             = $RpcProbe
        SmbProbe             = $SmbProbe
        WinRmProbe           = $WinRmProbe
        FallbackProbe        = $FallbackProbe
        Status               = $Status
        ErrorCategory        = $ErrorCategory
        ErrorMessage         = $ErrorMessage
        ProbeSummary         = $ProbeSummary
      }
    }

    function Get-NativeToolPath {
      param([Parameter(Mandatory)][string]$ToolName)
      try {
        $cmd = Get-Command $ToolName -ErrorAction Stop
        return $cmd.Source
      } catch {
        return $null
      }
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
        FilePath  = $FilePath
        Arguments = ($Arguments -join ' ')
        ExitCode  = $exitCode
        Output    = @($lines)
        Text      = ((@($lines) | Where-Object { $_ }) -join " | ")
        Exception = $thrown
      }
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

    function Test-UsableIdentityValue {
      param([string]$Value)
      if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
      $v = $Value.Trim()
      $badValues = @(
        '0',
        '00000000',
        'unknown',
        'none',
        'n/a',
        'na',
        'null',
        'default string',
        'system serial number',
        'to be filled by o.e.m.',
        'to be filled by oem',
        'not specified'
      )
      return ($badValues -notcontains $v.ToLowerInvariant())
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

    function Get-NetBiosNameFromNbtstat {
      param([string[]]$Lines)
      foreach ($line in @($Lines)) {
        if ($line -match '^\s*([^\s<]+)\s+<00>\s+UNIQUE\s+Registered') {
          return $matches[1].Trim()
        }
      }
      return ''
    }

    function Get-NmapPortStates {
      param([string[]]$Lines)
      $states = @{}
      foreach ($line in @($Lines)) {
        if ($line -match '^\s*(135|139|445|3389|5985|5986)/tcp\s+(open|closed|filtered|unfiltered|open\|filtered|closed\|filtered)\b') {
          $states[$matches[1]] = $matches[2]
        }
      }
      $states
    }

    function Convert-PortStateSummary {
      param([hashtable]$States)
      if (-not $States -or $States.Count -eq 0) { return '' }
      $orderedPorts = @('135','139','445','3389','5985','5986')
      $parts = @()
      foreach ($port in $orderedPorts) {
        if ($States.ContainsKey($port)) { $parts += ("{0}:{1}" -f $port, $States[$port]) }
      }
      $parts -join ';'
    }

    function Get-FailureProbeCategory {
      param(
        [hashtable]$States,
        [string[]]$Messages
      )

      $text = ((@($Messages) | Where-Object { $_ }) -join ' ').ToLowerInvariant()
      if ($text -match 'access is denied|access denied|logon failure|privilege') { return 'ACCESS_DENIED' }
      if ($text -match 'wmic.*not.*found|not recognized|could not find.*wmic') { return 'WMIC_NOT_AVAILABLE' }
      if ($text -match 'network path was not found|0x80070035|host not found|could not be found|no such host|unknown host|node.*error') { return 'HOSTNAME_UNRESOLVED_OR_UNREACHABLE' }

      if ($States -and $States.ContainsKey('135')) {
        if ($States['135'] -in @('filtered','closed','closed|filtered')) { return 'RPC_PORT_BLOCKED' }
        if ($States['135'] -eq 'open') {
          if ($States.ContainsKey('445') -and $States['445'] -in @('filtered','closed','closed|filtered')) { return 'SMB_PORT_BLOCKED' }
          return 'WMI_RPC_PATH_FAILED_AFTER_ENDPOINT_MAPPER'
        }
      }

      if ($text -match 'rpc server is unavailable|0x800706ba|rpc unavailable') { return 'RPC_UNAVAILABLE_OR_FILTERED' }
      if ($text -match 'invalid namespace|provider load failure|wmi|winmgmt|repository') { return 'WMI_SERVICE_OR_REPOSITORY_PROBLEM' }
      if ($text -match 'timed out|timeout') { return 'TIMEOUT' }
      if ($text -match 'no usable bios|no serial') { return 'SERIAL_NOT_RETURNED' }
      if ($text -match 'no usable mac|no mac') { return 'MAC_NOT_RETURNED' }
      return 'REMOTE_IDENTITY_PROBE_FAILED'
    }

    function Invoke-WmiRpcFailureProbe {
      param(
        [string]$Computer,
        [bool]$Local,
        [string]$NmapPath,
        [string]$NbtstatPath
      )

      $summary = @()
      $states = @{}
      $rpcProbe = ''
      $smbProbe = ''
      $winRmProbe = ''
      $fallbackProbe = ''
      $extraMacs = @()
      $extraName = ''

      if ($NmapPath -and -not $Local) {
        # Nmap is called with the hostname supplied by the user. The script does not
        # pre-resolve the hostname or export resolved IP addresses.
        $nmapProbe = Invoke-NativeCommand -FilePath $NmapPath -Arguments @('-sT','-Pn','--system-dns','-p','135,139,445,3389,5985,5986', $Computer)
        $states = Get-NmapPortStates -Lines $nmapProbe.Output
        $portSummary = Convert-PortStateSummary -States $states
        if ($portSummary) {
          $summary += "Nmap port probe: $portSummary"
          if ($states.ContainsKey('135')) { $rpcProbe = "135/tcp $($states['135'])" }
          if ($states.ContainsKey('445')) { $smbProbe = "445/tcp $($states['445'])" }
          $wrm = @()
          if ($states.ContainsKey('5985')) { $wrm += "5985/tcp $($states['5985'])" }
          if ($states.ContainsKey('5986')) { $wrm += "5986/tcp $($states['5986'])" }
          $winRmProbe = ($wrm -join ';')
        } else {
          $summary += "Nmap ran but did not return parseable port states. Output: $($nmapProbe.Text)"
        }
        $nmapMacs = @(Get-MacAddressesFromText -Lines $nmapProbe.Output)
        if ($nmapMacs.Count -gt 0) {
          $extraMacs += $nmapMacs
          $summary += 'Nmap returned MAC evidence'
        }
      } else {
        $summary += 'Nmap not available or local target; skipped port fallback probe'
      }

      if ($NbtstatPath) {
        $nbtArgs = if ($Local) { @('-n') } else { @('-a', $Computer) }
        $nbtProbe = Invoke-NativeCommand -FilePath $NbtstatPath -Arguments $nbtArgs
        $extraName = Get-NetBiosNameFromNbtstat -Lines $nbtProbe.Output
        $nbtMacs = @(Get-MacAddressesFromText -Lines $nbtProbe.Output)
        if ($nbtMacs.Count -gt 0) {
          $extraMacs += $nbtMacs
          $summary += 'NBTSTAT returned MAC evidence during failure probe'
        } else {
          $summary += "NBTSTAT failure probe returned no MAC. Output: $($nbtProbe.Text)"
        }
      }

      $fallbackProbe = ($summary -join ' || ')
      [pscustomobject]@{
        RpcProbe      = $rpcProbe
        SmbProbe      = $smbProbe
        WinRmProbe    = $winRmProbe
        FallbackProbe = $fallbackProbe
        PortStates    = $states
        MACAddress    = (($extraMacs | Where-Object { $_ } | Sort-Object -Unique) -join ';')
        ReportedName  = $extraName
      }
    }

    $wmicPath = Get-NativeToolPath -ToolName 'wmic.exe'
    $nbtstatPath = Get-NativeToolPath -ToolName 'nbtstat.exe'
    $getmacPath = Get-NativeToolPath -ToolName 'getmac.exe'
    $nmapPath = Get-NativeToolPath -ToolName 'nmap.exe'

    $serial = ''
    $serialSource = ''
    $reportedName = ''
    $reportedNameSource = ''
    $manufacturer = ''
    $model = ''
    $macs = @()
    $macSource = @()
    $errors = @()
    $probeSummary = @()
    $rpcProbe = ''
    $smbProbe = ''
    $winRmProbe = ''
    $fallbackProbe = ''

    if ($wmicPath) {
      $nodeArgs = @()
      if (-not $isLocal) { $nodeArgs += "/node:$Computer" }

      $biosProbe = Invoke-NativeCommand -FilePath $wmicPath -Arguments ($nodeArgs + @('bios','get','SerialNumber','/value'))
      $biosSerials = @(Get-WmicValues -Probe $biosProbe -Key 'SerialNumber' | Where-Object { Test-UsableIdentityValue $_ })
      if ($biosSerials.Count -gt 0) {
        $serial = $biosSerials[0]
        $serialSource = 'wmic:Win32_BIOS.SerialNumber'
        $probeSummary += 'Serial OK from WMIC BIOS'
      } else {
        $errors += "WMIC BIOS serial failed or blank. Output: $($biosProbe.Text)"
      }

      $systemProbe = Invoke-NativeCommand -FilePath $wmicPath -Arguments ($nodeArgs + @('computersystem','get','Name,Manufacturer,Model','/value'))
      $systemNames = @(Get-WmicValues -Probe $systemProbe -Key 'Name' | Where-Object { Test-UsableIdentityValue $_ })
      if ($systemNames.Count -gt 0) {
        $reportedName = $systemNames[0]
        $reportedNameSource = 'wmic:Win32_ComputerSystem.Name'
      } else {
        $errors += "WMIC computer system name failed or blank. Output: $($systemProbe.Text)"
      }
      $manufacturers = @(Get-WmicValues -Probe $systemProbe -Key 'Manufacturer' | Where-Object { Test-UsableIdentityValue $_ })
      if ($manufacturers.Count -gt 0) { $manufacturer = $manufacturers[0] }
      $models = @(Get-WmicValues -Probe $systemProbe -Key 'Model' | Where-Object { Test-UsableIdentityValue $_ })
      if ($models.Count -gt 0) { $model = $models[0] }

      if (-not (Test-UsableIdentityValue $serial)) {
        $productProbe = Invoke-NativeCommand -FilePath $wmicPath -Arguments ($nodeArgs + @('csproduct','get','IdentifyingNumber,Name,Vendor','/value'))
        $productSerials = @(Get-WmicValues -Probe $productProbe -Key 'IdentifyingNumber' | Where-Object { Test-UsableIdentityValue $_ })
        if ($productSerials.Count -gt 0) {
          $serial = $productSerials[0]
          $serialSource = 'wmic:Win32_ComputerSystemProduct.IdentifyingNumber'
          $probeSummary += 'Serial OK from WMIC CSProduct fallback'
        } else {
          $errors += "WMIC CSProduct serial fallback failed or blank. Output: $($productProbe.Text)"
        }
      }

      $nicProbe = Invoke-NativeCommand -FilePath $wmicPath -Arguments ($nodeArgs + @('nicconfig','where','IPEnabled=TRUE','get','MACAddress','/value'))
      $wmicMacs = @(Get-WmicValues -Probe $nicProbe -Key 'MACAddress' | ForEach-Object { ConvertTo-StandardMac $_ } | Where-Object { $_ })
      if ($wmicMacs.Count -gt 0) {
        $macs += $wmicMacs
        $macSource += 'wmic:Win32_NetworkAdapterConfiguration.MACAddress'
        $probeSummary += 'MAC OK from WMIC NICConfig'
      } else {
        $errors += "WMIC MAC query failed or blank. Output: $($nicProbe.Text)"
      }
    } else {
      $errors += 'wmic.exe is not available on this workstation, so remote serial collection cannot run from this script.'
    }

    if ($nbtstatPath) {
      $nbtArgs = if ($isLocal) { @('-n') } else { @('-a', $Computer) }
      $nbtProbe = Invoke-NativeCommand -FilePath $nbtstatPath -Arguments $nbtArgs
      $nbtName = Get-NetBiosNameFromNbtstat -Lines $nbtProbe.Output
      if (-not $reportedName -and $nbtName) {
        $reportedName = $nbtName
        $reportedNameSource = 'nbtstat:NetBIOS <00>'
      }
      $nbtMacs = @(Get-MacAddressesFromText -Lines $nbtProbe.Output)
      if ($nbtMacs.Count -gt 0) {
        $macs += $nbtMacs
        $macSource += 'nbtstat:MAC Address'
        $probeSummary += 'MAC fallback OK from nbtstat'
      } else {
        $errors += "NBTSTAT did not return a MAC/name. Output: $($nbtProbe.Text)"
      }
    } else {
      $errors += 'nbtstat.exe is not available for MAC/name fallback.'
    }

    if ($getmacPath) {
      $getmacArgs = if ($isLocal) { @('/fo','csv','/nh') } else { @('/s', $Computer, '/fo','csv','/nh') }
      $getmacProbe = Invoke-NativeCommand -FilePath $getmacPath -Arguments $getmacArgs
      $getmacMacs = @(Get-MacAddressesFromText -Lines $getmacProbe.Output)
      if ($getmacMacs.Count -gt 0) {
        $macs += $getmacMacs
        $macSource += 'getmac.exe'
        $probeSummary += 'MAC fallback OK from getmac'
      } else {
        $errors += "GETMAC did not return a MAC. Output: $($getmacProbe.Text)"
      }
    } else {
      $errors += 'getmac.exe is not available for MAC fallback.'
    }

    $macs = @($macs | Where-Object { $_ } | Sort-Object -Unique)
    $macSource = @($macSource | Where-Object { $_ } | Sort-Object -Unique)

    $serialOk = Test-UsableIdentityValue $serial
    $macOk = $macs.Count -gt 0

    # If WMI/RPC-backed identity collection fails or only partially works, run a
    # separate native failure probe. This does not magically recover serials when
    # WMI/RPC is blocked; it explains whether RPC/SMB/WinRM appears blocked/open
    # and tries one last hostname-based MAC/name fallback.
    $shouldRunFailureProbe = (-not $serialOk) -or (-not $macOk) -or ((@($errors) -join ' ') -match 'rpc|0x800706ba|access denied|network path|wmi')
    $failureProbe = $null
    if ($shouldRunFailureProbe) {
      $failureProbe = Invoke-WmiRpcFailureProbe -Computer $Computer -Local $isLocal -NmapPath $nmapPath -NbtstatPath $nbtstatPath
      $rpcProbe = $failureProbe.RpcProbe
      $smbProbe = $failureProbe.SmbProbe
      $winRmProbe = $failureProbe.WinRmProbe
      $fallbackProbe = $failureProbe.FallbackProbe
      if (-not $reportedName -and $failureProbe.ReportedName) {
        $reportedName = $failureProbe.ReportedName
        $reportedNameSource = 'failure-probe:nbtstat:NetBIOS <00>'
      }
      if (-not $macOk -and $failureProbe.MACAddress) {
        $macs += ($failureProbe.MACAddress -split ';')
        $macs = @($macs | Where-Object { $_ } | Sort-Object -Unique)
        $macSource += 'failure-probe:nmap/nbtstat'
        $macSource = @($macSource | Where-Object { $_ } | Sort-Object -Unique)
        $macOk = $macs.Count -gt 0
      }
      if ($fallbackProbe) { $probeSummary += 'Failure probe completed' }
    }

    $identityWarning = ''
    $requestedShortName = $Computer.Split('.')[0]
    if ($reportedName -and $Computer -notin @('localhost','127.0.0.1','.') -and $reportedName.ToUpperInvariant() -ne $requestedShortName.ToUpperInvariant()) {
      $identityWarning = "Requested host '$Computer' reported itself as '$reportedName'. Check DNS or the host list before trusting this row."
    }

    if (-not $serialOk) { $errors += 'No usable BIOS/product serial was returned by WMIC. Serial cannot be collected remotely unless WMI/RPC or an approved inventory agent path is available.' }
    if (-not $macOk) { $errors += 'No usable MAC address was returned by WMIC, NBTSTAT, GETMAC, or the failure probe.' }

    $status = 'Query Failed'
    if ($serialOk -and $macOk) {
      $status = 'OK'
    } elseif ($serialOk -or $macOk) {
      $status = 'Partial Identity'
    }

    $errorCategory = ''
    if ($status -ne 'OK') {
      $states = if ($failureProbe) { $failureProbe.PortStates } else { @{} }
      $errorCategory = Get-FailureProbeCategory -States $states -Messages $errors
    }

    New-MachineInfoRecord `
      -Status $status `
      -ErrorCategory $errorCategory `
      -ErrorMessage ((@($errors) | Where-Object { $_ }) -join ' || ') `
      -Serial $serial `
      -SerialSource $serialSource `
      -MACAddress (($macs | Sort-Object -Unique) -join ';') `
      -MACSource (($macSource | Sort-Object -Unique) -join ';') `
      -ReportedComputerName $reportedName `
      -ReportedNameSource $reportedNameSource `
      -Model $model `
      -Manufacturer $manufacturer `
      -IdentityWarning $identityWarning `
      -RpcProbe $rpcProbe `
      -SmbProbe $smbProbe `
      -WinRmProbe $winRmProbe `
      -FallbackProbe $fallbackProbe `
      -ProbeSummary ((@($probeSummary) | Where-Object { $_ }) -join '; ')
  } -ArgumentList $Computer
}

function Get-MachineInfoFailureReason {
  param([Parameter(Mandatory)][object]$Row)

  $parts = @()

  if ($Row.IdentityWarning) {
    $parts += "Identity mismatch: $($Row.IdentityWarning)"
  }

  switch ($Row.ErrorCategory) {
    'ACCESS_DENIED' {
      $parts += 'Remote identity probe reached the host, but credentials or permissions were denied. Use an account allowed to query remote WMI/RPC or an approved inventory path.'
    }
    'WMIC_NOT_AVAILABLE' {
      $parts += 'wmic.exe is not available on the probe workstation, so native WMIC serial/MAC collection cannot run from here.'
    }
    'HOSTNAME_UNRESOLVED_OR_UNREACHABLE' {
      $parts += 'The hostname could not be resolved or reached by the native probe. Check hostlist spelling, DNS, stale records, and network path.'
    }
    'RPC_PORT_BLOCKED' {
      $parts += 'RPC endpoint mapper appears blocked or closed. Remote BIOS serial collection cannot work until RPC/WMI is allowed or another approved inventory source is used.'
    }
    'SMB_PORT_BLOCKED' {
      $parts += 'RPC endpoint mapper may be reachable, but SMB/admin-share support appears blocked. Remote WMI may fail because the management path is incomplete.'
    }
    'WMI_RPC_PATH_FAILED_AFTER_ENDPOINT_MAPPER' {
      $parts += 'TCP 135 appears open, but the WMI/RPC session still failed after endpoint mapping. Likely causes: dynamic RPC firewall range, target WMI service issue, DCOM policy, endpoint security, or permissions.'
    }
    'RPC_UNAVAILABLE_OR_FILTERED' {
      $parts += 'The target returned an RPC unavailable condition. This usually means firewall, VLAN ACL, endpoint policy, or WMI/RPC service availability is blocking the query.'
    }
    'WMI_SERVICE_OR_REPOSITORY_PROBLEM' {
      $parts += 'The host was contacted, but WMI provider/namespace/repository returned a problem. Check Winmgmt/WMI health on the endpoint.'
    }
    'TIMEOUT' {
      $parts += 'The probe timed out. The host may be slow, filtered, overloaded, or partially reachable.'
    }
    'SERIAL_NOT_RETURNED' {
      $parts += 'No usable BIOS/product serial was returned. Serial requires WMIC/WMI/RPC or an approved inventory agent path.'
    }
    'MAC_NOT_RETURNED' {
      $parts += 'No usable MAC address was returned by WMIC, NBTSTAT, GETMAC, or the fallback probe.'
    }
    'REMOTE_IDENTITY_PROBE_FAILED' {
      $parts += 'The native hostname-based identity probe failed, but the returned error did not match a more specific category. Review ErrorMessage and probe columns.'
    }
    default {
      if ($Row.Status -ne 'OK') {
        $parts += 'The machine did not return complete identity data. Review ErrorMessage, RPC/SMB/WinRM probe columns, and hostname identity warning.'
      }
    }
  }

  if ($Row.Status -eq 'Partial Identity') {
    $parts += 'Partial Identity means at least one strong identifier was found, but serial or MAC is still missing.'
  }
  if ($Row.Status -eq 'Query Failed') {
    $parts += 'Query Failed means neither the required serial+MAC identity set nor a complete fallback identity was collected.'
  }
  if (-not $Row.Serial) {
    $parts += 'Serial missing.'
  }
  if (-not $Row.MACAddress) {
    $parts += 'MAC missing.'
  }
  if ($Row.RpcProbe) { $parts += "RPC probe: $($Row.RpcProbe)." }
  if ($Row.SmbProbe) { $parts += "SMB probe: $($Row.SmbProbe)." }
  if ($Row.WinRmProbe) { $parts += "WinRM probe: $($Row.WinRmProbe)." }

  (($parts | Where-Object { $_ }) -join ' ')
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

$results = @($jobs | Receive-Job)
foreach ($row in $results) {
  $failureReason = Get-MachineInfoFailureReason -Row $row
  if ($row.PSObject.Properties.Name -contains 'FailureReason') {
    $row.FailureReason = $failureReason
  } else {
    $row | Add-Member -NotePropertyName FailureReason -NotePropertyValue $failureReason
  }
}

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
  $sortedResults = @($results | Sort-Object HostName)
  $failureRows = @($sortedResults | Where-Object { $_.Status -ne 'OK' -or $_.IdentityWarning })
  $okCount = @($sortedResults | Where-Object { $_.Status -eq 'OK' }).Count
  $partialCount = @($sortedResults | Where-Object { $_.Status -eq 'Partial Identity' }).Count
  $failedCount = @($sortedResults | Where-Object { $_.Status -eq 'Query Failed' }).Count
  $warningCount = @($sortedResults | Where-Object { $_.IdentityWarning }).Count

  $summaryRows = @(
    [pscustomobject]@{ Metric = 'Total hosts'; Count = $sortedResults.Count }
    [pscustomobject]@{ Metric = 'OK'; Count = $okCount }
    [pscustomobject]@{ Metric = 'Partial Identity'; Count = $partialCount }
    [pscustomobject]@{ Metric = 'Query Failed'; Count = $failedCount }
    [pscustomobject]@{ Metric = 'Identity Warnings'; Count = $warningCount }
  )

  $bodyParts = @()
  $bodyParts += $summaryRows | ConvertTo-Html -Fragment -PreContent '<h2>Run Summary</h2>'

  if ($failureRows.Count -gt 0) {
    $bodyParts += $failureRows |
      Select-Object HostName,ReportedComputerName,Status,ErrorCategory,FailureReason,RpcProbe,SmbProbe,WinRmProbe,IdentityWarning,ErrorMessage |
      ConvertTo-Html -Fragment -PreContent '<h2>Failures and Warnings - Reason for Failure</h2>'
  } else {
    $bodyParts += '<h2>Failures and Warnings - Reason for Failure</h2><p>No failed hosts or identity warnings were detected in this run.</p>'
  }

  $bodyParts += $sortedResults |
    Select-Object HostName,ReportedComputerName,Serial,SerialSource,MACAddress,MACSource,Model,Manufacturer,ReportedNameSource,IdentityWarning,RpcProbe,SmbProbe,WinRmProbe,FallbackProbe,Status,ErrorCategory,FailureReason,ErrorMessage,ProbeSummary |
    ConvertTo-Html -Fragment -PreContent '<h2>Machine Info - Hostname First Native Probe</h2>'

  ($bodyParts -join "`n") |
    ConvertTo-SuiteHtml `
      -Title 'Machine Info - Hostname First Native Probe' `
      -Subtitle "$(($sortedResults | Select-Object -ExpandProperty HostName -Unique).Count) host(s)" `
      -SummaryChips @("OK: $okCount", "Partial: $partialCount", "Failed: $failedCount", "Warnings: $warningCount") `
      -OutputPath $htmlPath
}