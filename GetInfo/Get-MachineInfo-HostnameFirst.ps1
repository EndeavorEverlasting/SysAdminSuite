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
  $reasons = @()
  $evidence = @()

  $ipconfigPath = (Get-Command ipconfig.exe -ErrorAction SilentlyContinue).Source
  $nltestPath = (Get-Command nltest.exe -ErrorAction SilentlyContinue).Source
  $nslookupPath = (Get-Command nslookup.exe -ErrorAction SilentlyContinue).Source
  $nmapPath = (Get-Command nmap.exe -ErrorAction SilentlyContinue).Source

  if ($ipconfigPath) {
    $ipconfig = Invoke-NativeCommand -FilePath $ipconfigPath -Arguments @('/all')
    $ipText = $ipconfig.Text
    if ($ipText -match 'nslijhs\.net' -or $ipText -match 'northwell') {
      $evidence += 'ipconfig shows Northwell/nslijhs network context'
    } else {
      $reasons += 'ipconfig did not show a Northwell/nslijhs DNS suffix or network context'
    }
    if ($ipText -match '(?i)guest') {
      $reasons += 'ipconfig appears to show guest network context'
    }
  } else {
    $reasons += 'ipconfig.exe is not available for network preflight'
  }

  if ($nltestPath) {
    $nltest = Invoke-NativeCommand -FilePath $nltestPath -Arguments @('/dsgetdc:nslijhs.net')
    if ($nltest.ExitCode -eq 0 -and $nltest.Text -match 'nslijhs\.net') {
      $evidence += 'nltest found a domain controller for nslijhs.net'
    } else {
      $reasons += "nltest could not locate a nslijhs.net domain controller. Output: $($nltest.Text)"
    }
  } else {
    $reasons += 'nltest.exe is not available for domain-controller preflight'
  }

  if ($nslookupPath) {
    $dnsProbe = Invoke-NativeCommand -FilePath $nslookupPath -Arguments @('SWBPNHPHPS01V')
    if ($dnsProbe.ExitCode -eq 0 -and $dnsProbe.Text -match '(?i)nslijhs\.net|Address') {
      $evidence += 'nslookup resolved an internal Northwell smoke target'
    } else {
      $reasons += "nslookup could not resolve internal smoke target SWBPNHPHPS01V. Output: $($dnsProbe.Text)"
    }
  } else {
    $reasons += 'nslookup.exe is not available for DNS preflight'
  }

  if ($nmapPath) {
    $portProbe = Invoke-NativeCommand -FilePath $nmapPath -Arguments @('-sT','-Pn','--system-dns','-p','445','SWBPNHPHPS01V')
    if ($portProbe.Text -match '445/tcp\s+open') {
      $evidence += 'nmap shows SMB/445 reachable to the Northwell smoke target'
    } elseif ($portProbe.Text -match '445/tcp\s+(filtered|closed)') {
      $reasons += "SMB/445 to Northwell smoke target is not open. Output: $($portProbe.Text)"
    } else {
      $reasons += "nmap did not return a clear SMB/445 result for SWBPNHPHPS01V. Output: $($portProbe.Text)"
    }
  } else {
    $reasons += 'nmap.exe is not available for WAB port preflight; continuing based on DNS/domain evidence only'
  }

  $hardFails = @($reasons | Where-Object { $_ -notmatch 'nmap\.exe is not available' })
  $isConnected = ($evidence.Count -ge 2 -and $hardFails.Count -eq 0)

  [pscustomobject]@{
    IsConnected = $isConnected
    Evidence    = ($evidence -join ' || ')
    Reasons     = ($reasons -join ' || ')
  }
}

$wabCheck = Test-NorthwellWabConnection
if (-not $wabCheck.IsConnected -and -not $Force) {
  $message = @"
Northwell WAB preflight failed. Get-MachineInfo-HostnameFirst did not run.

Reason(s): $($wabCheck.Reasons)
Evidence found: $($wabCheck.Evidence)

Connect to the Northwell WAB/enterprise network and rerun this script.
Use -Force only for approved lab testing when you intentionally want to bypass this guard.
"@
  Write-Error $message
  exit 20
}

if ($Force -and -not $wabCheck.IsConnected) {
  Write-Warning "Northwell WAB preflight failed but -Force was supplied. Reason(s): $($wabCheck.Reasons)"
}

$coreScript = Join-Path $PSScriptRoot 'Get-MachineInfo-HostnameFirst.Core.ps1'
if (-not (Test-Path -LiteralPath $coreScript)) {
  throw "Core script not found: $coreScript"
}

& $coreScript -ListPath $ListPath -OutputPath $OutputPath -Throttle $Throttle
