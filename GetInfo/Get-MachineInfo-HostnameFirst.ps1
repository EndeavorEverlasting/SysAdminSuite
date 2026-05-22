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
    # Serial collection still requires a working remote WMI/RPC path on the target.
    # If the network, firewall, endpoint policy, or permissions block that path,
    # the row reports a specific error category instead of pretending the host is OK.

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

    function Get-ErrorCategory {
      param([string[]]$Messages)
      $text = ((@($Messages) | Where-Object { $_ }) -join ' ').ToLowerInvariant()
      if (-not $text) { return 'UNKNOWN' }
      if ($text -match 'wmic.*not.*found|not recognized|could not find.*wmic') { return 'WMIC_NOT_AVAILABLE' }
      if ($text -match 'access is denied|access denied|logon failure|privilege') { return 'ACCESS_DENIED' }
      if ($text -match 'rpc server is unavailable|0x800706ba|rpc unavailable') { return 'RPC_UNAVAILABLE_OR_FILTERED' }
      if ($text -match 'network path was not found|0x80070035|host not found|could not be found|no such host|unknown host|node.*error') { return 'HOSTNAME_UNRESOLVED_OR_UNREACHABLE' }
      if ($text -match 'invalid namespace|provider load failure|wmi|winmgmt|repository') { return 'WMI_SERVICE_OR_REPOSITORY_PROBLEM' }
      if ($text -match 'timed out|timeout') { return 'TIMEOUT' }
      if ($text -match 'no serial') { return 'SERIAL_NOT_RETURNED' }
      if ($text -match 'no mac') { return 'MAC_NOT_RETURNED' }
      return 'REMOTE_IDENTITY_PROBE_FAILED'
    }

    $wmicPath = Get-NativeToolPath -ToolName 'wmic.exe'
    $nbtstatPath = Get-NativeToolPath -ToolName 'nbtstat.exe'
    $getmacPath = Get-NativeToolPath -ToolName 'getmac.exe'

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

    $identityWarning = ''
    $requestedShortName = $Computer.Split('.')[0]
    if ($reportedName -and $Computer -notin @('localhost','127.0.0.1','.') -and $reportedName.ToUpperInvariant() -ne $requestedShortName.ToUpperInvariant()) {
      $identityWarning = "Requested host '$Computer' reported itself as '$reportedName'. Check DNS or the host list before trusting this row."
    }

    $serialOk = Test-UsableIdentityValue $serial
    $macOk = $macs.Count -gt 0
    if (-not $serialOk) { $errors += 'No usable BIOS/product serial was returned by WMIC.' }
    if (-not $macOk) { $errors += 'No usable MAC address was returned by WMIC, NBTSTAT, or GETMAC.' }

    $status = 'Query Failed'
    if ($serialOk -and $macOk) {
      $status = 'OK'
    } elseif ($serialOk -or $macOk) {
      $status = 'Partial Identity'
    }

    $errorCategory = ''
    if ($status -ne 'OK') {
      $errorCategory = Get-ErrorCategory -Messages $errors
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
      -ProbeSummary ((@($probeSummary) | Where-Object { $_ }) -join '; ')
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
    Select-Object HostName,ReportedComputerName,Serial,SerialSource,MACAddress,MACSource,Model,Manufacturer,ReportedNameSource,IdentityWarning,Status,ErrorCategory,ErrorMessage,ProbeSummary |
    ConvertTo-Html -Fragment -PreContent '<h2>Machine Info - Hostname First Native Probe</h2>' |
    ConvertTo-SuiteHtml -Title 'Machine Info - Hostname First Native Probe' -Subtitle "$(($results | Select-Object -ExpandProperty HostName -Unique).Count) host(s)" -OutputPath $htmlPath
}