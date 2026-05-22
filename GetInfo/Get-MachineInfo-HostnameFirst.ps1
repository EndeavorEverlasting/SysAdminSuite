param(
  [string]$ListPath   = "C:\Temp\hostlist.txt",
  [string]$OutputPath = (Join-Path $PSScriptRoot 'Output\MachineInfo\MachineInfo_HostnameFirst_Output.csv'),
  [int]$Throttle      = 15,
  [switch]$Force
)

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
    ExitCode  = $exitCode
    Output    = @($lines)
    Text      = ((@($lines) | Where-Object { $_ }) -join ' | ')
    Exception = $thrown
  }
}

function Test-NorthwellWabConnection {
  # Preflight order is intentional and mirrors the Cybernet/WAB field rule:
  #   1. Nmap first: prove the network path with a read-only port check.
  #   2. Active Directory second: prove nslijhs.net/DC context.
  #   3. SCCM third: collect client-management evidence when present.
  #   4. Other network probes last: DNS suffix, ipconfig, and smoke DNS lookups.
  $reasons = @()
  $evidence = @()
  $softWarnings = @()

  $nmapPath = (Get-Command nmap.exe -ErrorAction SilentlyContinue).Source
  $nltestPath = (Get-Command nltest.exe -ErrorAction SilentlyContinue).Source
  $scPath = (Get-Command sc.exe -ErrorAction SilentlyContinue).Source
  $regPath = (Get-Command reg.exe -ErrorAction SilentlyContinue).Source
  $ipconfigPath = (Get-Command ipconfig.exe -ErrorAction SilentlyContinue).Source
  $nslookupPath = (Get-Command nslookup.exe -ErrorAction SilentlyContinue).Source

  # 1. Nmap first.
  if ($nmapPath) {
    $portProbe = Invoke-NativeCommand -FilePath $nmapPath -Arguments @('-sT','-Pn','--system-dns','-p','445','SWBPNHPHPS01V')
    if ($portProbe.Text -match '445/tcp\s+open') {
      $evidence += '01_NMAP: SMB/445 reachable to Northwell smoke target SWBPNHPHPS01V'
    } elseif ($portProbe.Text -match '445/tcp\s+(filtered|closed)') {
      $reasons += "01_NMAP_FAIL: SMB/445 to Northwell smoke target is not open. Output: $($portProbe.Text)"
    } else {
      $reasons += "01_NMAP_FAIL: nmap did not return a clear SMB/445 result for SWBPNHPHPS01V. Output: $($portProbe.Text)"
    }
  } else {
    $reasons += '01_NMAP_FAIL: nmap.exe is required for this WAB guard and was not found in PATH'
  }

  # 2. Active Directory second.
  if ($nltestPath) {
    $nltest = Invoke-NativeCommand -FilePath $nltestPath -Arguments @('/dsgetdc:nslijhs.net')
    if ($nltest.ExitCode -eq 0 -and $nltest.Text -match 'nslijhs\.net') {
      $evidence += '02_AD: nltest found a domain controller for nslijhs.net'
    } else {
      $reasons += "02_AD_FAIL: nltest could not locate a nslijhs.net domain controller. Output: $($nltest.Text)"
    }
  } else {
    $reasons += '02_AD_FAIL: nltest.exe is not available for Active Directory preflight'
  }

  # 3. SCCM third. This is a management-evidence probe, not a hard network gate.
  # Some workstations may not expose SCCM client evidence to non-admin shells, so
  # missing SCCM evidence is captured as a warning unless Nmap/AD also failed.
  $sccmEvidenceFound = $false
  if ($scPath) {
    $ccmService = Invoke-NativeCommand -FilePath $scPath -Arguments @('query','ccmexec')
    if ($ccmService.Text -match 'SERVICE_NAME:\s+ccmexec' -and $ccmService.Text -match 'STATE') {
      $evidence += '03_SCCM: ccmexec service is present'
      $sccmEvidenceFound = $true
    } else {
      $softWarnings += "03_SCCM_WARN: ccmexec service was not confirmed. Output: $($ccmService.Text)"
    }
  } else {
    $softWarnings += '03_SCCM_WARN: sc.exe is not available for SCCM service preflight'
  }

  if ($regPath) {
    $ccmReg = Invoke-NativeCommand -FilePath $regPath -Arguments @('query','HKLM\SOFTWARE\Microsoft\SMS\Mobile Client','/v','AssignedSiteCode')
    if ($ccmReg.ExitCode -eq 0 -and $ccmReg.Text -match 'AssignedSiteCode') {
      $evidence += '03_SCCM: SCCM AssignedSiteCode registry value is present'
      $sccmEvidenceFound = $true
    } else {
      $softWarnings += "03_SCCM_WARN: SCCM AssignedSiteCode was not confirmed. Output: $($ccmReg.Text)"
    }
  } else {
    $softWarnings += '03_SCCM_WARN: reg.exe is not available for SCCM registry preflight'
  }

  if (-not $sccmEvidenceFound) {
    $softWarnings += '03_SCCM_WARN: SCCM evidence was not confirmed; continuing only if Nmap and AD passed'
  }

  # 4. Other network probes last.
  if ($ipconfigPath) {
    $ipconfig = Invoke-NativeCommand -FilePath $ipconfigPath -Arguments @('/all')
    $ipText = $ipconfig.Text
    if ($ipText -match 'nslijhs\.net' -or $ipText -match 'northwell') {
      $evidence += '04_NETWORK: ipconfig shows Northwell/nslijhs network context'
    } else {
      $reasons += '04_NETWORK_FAIL: ipconfig did not show a Northwell/nslijhs DNS suffix or network context'
    }
    if ($ipText -match '(?i)guest') {
      $reasons += '04_NETWORK_FAIL: ipconfig appears to show guest network context'
    }
  } else {
    $reasons += '04_NETWORK_FAIL: ipconfig.exe is not available for network preflight'
  }

  if ($nslookupPath) {
    $dnsProbe = Invoke-NativeCommand -FilePath $nslookupPath -Arguments @('SWBPNHPHPS01V')
    if ($dnsProbe.ExitCode -eq 0 -and $dnsProbe.Text -match '(?i)nslijhs\.net|Address') {
      $evidence += '04_NETWORK: nslookup resolved internal Northwell smoke target SWBPNHPHPS01V'
    } else {
      $reasons += "04_NETWORK_FAIL: nslookup could not resolve internal smoke target SWBPNHPHPS01V. Output: $($dnsProbe.Text)"
    }
  } else {
    $reasons += '04_NETWORK_FAIL: nslookup.exe is not available for DNS preflight'
  }

  $isConnected = (
    ($evidence -match '^01_NMAP:').Count -ge 1 -and
    ($evidence -match '^02_AD:').Count -ge 1 -and
    ($evidence -match '^04_NETWORK:').Count -ge 1 -and
    $reasons.Count -eq 0
  )

  [pscustomobject]@{
    IsConnected = $isConnected
    Evidence    = ($evidence -join ' || ')
    Warnings    = ($softWarnings -join ' || ')
    Reasons     = ($reasons -join ' || ')
  }
}

$wabCheck = Test-NorthwellWabConnection
if (-not $wabCheck.IsConnected -and -not $Force) {
  $message = @"
Northwell WAB preflight failed. Get-MachineInfo-HostnameFirst did not run.

Required probe order:
1. Nmap first
2. Active Directory second
3. SCCM third
4. Other network probes last

Reason(s): $($wabCheck.Reasons)
Warning(s): $($wabCheck.Warnings)
Evidence found: $($wabCheck.Evidence)

Connect to the Northwell WAB/enterprise network and rerun this script.
Use -Force only for approved lab testing when you intentionally want to bypass this guard.
"@
  Write-Error $message
  exit 20
}

if ($Force -and -not $wabCheck.IsConnected) {
  Write-Warning "Northwell WAB preflight failed but -Force was supplied. Reason(s): $($wabCheck.Reasons) Warning(s): $($wabCheck.Warnings)"
}

if ($wabCheck.Warnings) {
  Write-Warning "Northwell WAB preflight warnings: $($wabCheck.Warnings)"
}

$coreScript = Join-Path $PSScriptRoot 'Get-MachineInfo-HostnameFirst.Core.ps1'
if (-not (Test-Path -LiteralPath $coreScript)) {
  throw "Core script not found: $coreScript"
}

& $coreScript -ListPath $ListPath -OutputPath $OutputPath -Throttle $Throttle
