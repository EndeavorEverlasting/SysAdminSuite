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
  # This preflight only decides whether the script is allowed to run from the
  # Northwell/WAB enterprise path. It does NOT enforce the hostname probe order.
  # Hostname probing still follows: Nmap -> AD -> SCCM -> other native probes.
  $reasons = @()
  $evidence = @()
  $warnings = @()

  $ipconfigPath = (Get-Command ipconfig.exe -ErrorAction SilentlyContinue).Source
  $nslookupPath = (Get-Command nslookup.exe -ErrorAction SilentlyContinue).Source
  $nltestPath = (Get-Command nltest.exe -ErrorAction SilentlyContinue).Source

  if ($ipconfigPath) {
    $ipconfig = Invoke-NativeCommand -FilePath $ipconfigPath -Arguments @('/all')
    $ipText = $ipconfig.Text

    if ($ipText -match '(?i)nslijhs\.net|northwell|wab') {
      $evidence += 'ipconfig shows Northwell/WAB/nslijhs network context'
    }
    if ($ipText -match '(?i)guest') {
      $reasons += 'ipconfig appears to show guest network context'
    }
  } else {
    $warnings += 'ipconfig.exe is not available for WAB preflight'
  }

  if ($nslookupPath) {
    $dnsProbe = Invoke-NativeCommand -FilePath $nslookupPath -Arguments @('SWBPNHPHPS01V')
    if ($dnsProbe.ExitCode -eq 0 -and $dnsProbe.Text -match '(?i)nslijhs\.net') {
      $evidence += 'nslookup resolved internal Northwell smoke target SWBPNHPHPS01V'
    } else {
      $warnings += "nslookup did not confirm SWBPNHPHPS01V as nslijhs.net. Output: $($dnsProbe.Text)"
    }
  } else {
    $warnings += 'nslookup.exe is not available for WAB DNS preflight'
  }

  if ($nltestPath) {
    $adProbe = Invoke-NativeCommand -FilePath $nltestPath -Arguments @('/dsgetdc:nslijhs.net')
    if ($adProbe.ExitCode -eq 0 -and $adProbe.Text -match '(?i)nslijhs\.net') {
      $evidence += 'nltest found a nslijhs.net domain controller'
    } else {
      $warnings += "nltest did not confirm nslijhs.net domain-controller access. Output: $($adProbe.Text)"
    }
  } else {
    $warnings += 'nltest.exe is not available for WAB AD evidence'
  }

  if ($evidence.Count -eq 0) {
    $reasons += 'No Northwell/WAB evidence was found. Expected one of: nslijhs.net DNS suffix, internal smoke-host DNS, or nslijhs.net domain-controller evidence.'
  }

  [pscustomobject]@{
    IsConnected = ($reasons.Count -eq 0 -and $evidence.Count -gt 0)
    Evidence    = ($evidence -join ' || ')
    Warnings    = ($warnings -join ' || ')
    Reasons     = ($reasons -join ' || ')
  }
}

Write-Host "[START] Get-MachineInfo-HostnameFirst launcher" -ForegroundColor Cyan
Write-Host "[INFO] ListPath: $ListPath" -ForegroundColor Gray
Write-Host "[INFO] OutputPath: $OutputPath" -ForegroundColor Gray
Write-Host "[INFO] Running Northwell/WAB network preflight. This only blocks guest/wrong-network use." -ForegroundColor Cyan

$wabCheck = Test-NorthwellWabConnection
if (-not $wabCheck.IsConnected -and -not $Force) {
  $message = @"
Northwell WAB preflight failed. Get-MachineInfo-HostnameFirst did not run.

This preflight does NOT require Nmap/AD/SCCM order. That order is only enforced during hostname probing.

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

Write-Host "[PASS] WAB preflight passed or was forced." -ForegroundColor Green
if ($wabCheck.Evidence) { Write-Host "[EVIDENCE] $($wabCheck.Evidence)" -ForegroundColor Green }
if ($wabCheck.Warnings) { Write-Warning "Northwell WAB preflight warnings: $($wabCheck.Warnings)" }

$coreScript = Join-Path $PSScriptRoot 'Get-MachineInfo-HostnameFirst.Core.ps1'
if (-not (Test-Path -LiteralPath $coreScript)) { throw "Core script not found: $coreScript" }

Write-Host "[INFO] Handing off to protected core script..." -ForegroundColor Cyan
& $coreScript -ListPath $ListPath -OutputPath $OutputPath -Throttle $Throttle -PreflightPassed
Write-Host "[DONE] Get-MachineInfo-HostnameFirst finished." -ForegroundColor Green
