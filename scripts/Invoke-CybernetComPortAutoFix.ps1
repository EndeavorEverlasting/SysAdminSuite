[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$Restart,
  [switch]$Force,
  [string]$EvidenceRoot = 'C:\Temp\CybernetCOM'
)

$ErrorActionPreference = 'Stop'

function Test-RunningAsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Step {
  param([string]$Message)
  Write-Host "[Cybernet COM AutoFix] $Message"
}

function Invoke-CmdCapture {
  param(
    [Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)][string]$OutputPath
  )
  cmd.exe /c "$Command > `"$OutputPath`" 2>&1"
}

function Get-ComNumberFromName {
  param([string]$Name)
  if ($Name -match '\(COM(?<port>\d+)\)') { return [int]$Matches.port }
  return $null
}

function Get-LocalCommunicationPorts {
  $pnp = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)
  $ports = @()
  foreach ($device in $pnp) {
    $portNumber = Get-ComNumberFromName -Name ([string]$device.Name)
    if ($null -eq $portNumber) { continue }
    if ([string]$device.Name -notmatch '^Communications Port \(COM\d+\)$') { continue }
    $ports += [pscustomobject]@{
      Name = [string]$device.Name
      CurrentPort = $portNumber
      PNPDeviceID = [string]$device.PNPDeviceID
      Status = [string]$device.Status
      RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($device.PNPDeviceID)\Device Parameters"
    }
  }
  return @($ports | Sort-Object CurrentPort)
}

function Test-FintekSerialPresent {
  $devices = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object {
    ([string]$_.Name -match 'FINTEK') -or
    ([string]$_.Name -match 'Multi-port serial') -or
    ([string]$_.PNPClass -eq 'MultiPortSerial')
  })
  return $devices.Count -gt 0
}

if (-not (Test-RunningAsAdministrator)) {
  throw 'Run this from an elevated Command Prompt or through Run-CybernetComPortAutoFix.cmd.'
}

$runStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir = Join-Path $EvidenceRoot "autofix_$runStamp"
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$logPath = Join-Path $runDir 'autofix-transcript.txt'
$summaryPath = Join-Path $runDir 'autofix-summary.json'

Start-Transcript -Path $logPath -Force | Out-Null
try {
  Write-Step "Evidence folder: $runDir"
  hostname | Set-Content -LiteralPath (Join-Path $runDir 'hostname.txt') -Encoding ASCII
  Get-Date -Format s | Set-Content -LiteralPath (Join-Path $runDir 'started-at.txt') -Encoding ASCII
  Invoke-CmdCapture -Command 'reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM' -OutputPath (Join-Path $runDir 'serialcomm-before.txt')
  Invoke-CmdCapture -Command 'pnputil /enum-devices /class Ports' -OutputPath (Join-Path $runDir 'ports-before.txt')
  Invoke-CmdCapture -Command 'pnputil /enum-devices /class MultiPortSerial' -OutputPath (Join-Path $runDir 'multiport-before.txt')
  Get-CimInstance Win32_PnPEntity | Sort-Object Name | Select-Object Name,PNPClass,PNPDeviceID,Status | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'pnp-before.json') -Encoding UTF8

  $fintekPresent = Test-FintekSerialPresent
  $ports = @(Get-LocalCommunicationPorts)
  $currentPorts = @($ports | Select-Object -ExpandProperty CurrentPort)

  Write-Step "Detected communication ports: $($currentPorts -join ', ')"
  Write-Step "FINTEK or multi-port serial device present: $fintekPresent"

  $alreadyCorrect = ($currentPorts.Count -eq 4 -and (@($currentPorts | Sort-Object) -join ',') -eq '1,2,3,4')
  if ($alreadyCorrect) {
    Write-Step 'COM ports are already COM1-COM4. Capturing state and exiting without changes.'
    Invoke-CmdCapture -Command 'reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM' -OutputPath (Join-Path $runDir 'serialcomm-after.txt')
    Invoke-CmdCapture -Command 'pnputil /enum-devices /class Ports' -OutputPath (Join-Path $runDir 'ports-after.txt')
    [pscustomobject]@{
      status = 'already-correct'
      evidence_dir = $runDir
      fintek_present = $fintekPresent
      detected_ports = $currentPorts
      applied = $false
      restart_requested = $false
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    return
  }

  if (-not $fintekPresent -and -not $Force) {
    throw 'FINTEK or multi-port serial device was not detected. Use -Force only if a lead confirms this is still a Cybernet COM repair target.'
  }
  if ($ports.Count -ne 4 -and -not $Force) {
    throw "Expected exactly 4 active Communications Port devices, found $($ports.Count). Use -Force only after a lead confirms the target."
  }
  if (((@($currentPorts | Sort-Object) -join ',') -ne '3,4,5,6') -and -not $Force) {
    throw "Expected the known failed map COM3-COM6, found $($currentPorts -join ','). Use -Force only after a lead confirms the target."
  }

  $arbiterExportPath = Join-Path $runDir 'COMNameArbiter-before.reg'
  & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\COM Name Arbiter' $arbiterExportPath /y | Out-File -FilePath (Join-Path $runDir 'reg-export-output.txt') -Encoding ASCII

  $mapping = @()
  $sortedPorts = @($ports | Sort-Object CurrentPort)
  for ($i = 0; $i -lt $sortedPorts.Count; $i++) {
    $targetPort = 'COM{0}' -f ($i + 1)
    $mapping += [pscustomobject]@{
      name = $sortedPorts[$i].Name
      pnp_device_id = $sortedPorts[$i].PNPDeviceID
      current_port = ('COM{0}' -f $sortedPorts[$i].CurrentPort)
      target_port = $targetPort
      registry_path = $sortedPorts[$i].RegistryPath
    }
  }

  $mapping | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDir 'port-mapping-plan.json') -Encoding UTF8

  if (-not $Apply) {
    Write-Step 'Dry run only. Re-run with -Apply to reset COM reservations and assign COM1-COM4.'
    [pscustomobject]@{
      status = 'dry-run'
      evidence_dir = $runDir
      fintek_present = $fintekPresent
      detected_ports = $currentPorts
      planned_mapping = $mapping
      applied = $false
      restart_requested = $false
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    return
  }

  Write-Step 'Resetting COM Name Arbiter reservation bitmap.'
  & reg.exe add 'HKLM\SYSTEM\CurrentControlSet\Control\COM Name Arbiter' /v ComDB /t REG_BINARY /d 0000000000000000000000000000000000000000000000000000000000000000 /f | Out-File -FilePath (Join-Path $runDir 'reg-reset-output.txt') -Encoding ASCII

  foreach ($item in $mapping) {
    if (-not (Test-Path -LiteralPath $item.registry_path)) {
      throw "Device Parameters registry path not found: $($item.registry_path)"
    }
    Write-Step "Assigning $($item.current_port) to $($item.target_port): $($item.name)"
    Set-ItemProperty -LiteralPath $item.registry_path -Name PortName -Value $item.target_port
  }

  Invoke-CmdCapture -Command 'reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM' -OutputPath (Join-Path $runDir 'serialcomm-after.txt')
  Invoke-CmdCapture -Command 'pnputil /enum-devices /class Ports' -OutputPath (Join-Path $runDir 'ports-after.txt')

  [pscustomobject]@{
    status = 'applied'
    evidence_dir = $runDir
    fintek_present = $fintekPresent
    detected_ports = $currentPorts
    applied_mapping = $mapping
    applied = $true
    restart_requested = [bool]$Restart
    restart_note = if ($Restart) { 'Restart requested by launcher.' } else { 'Restart not requested. Restart manually before final app binding.' }
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

  Write-Step "Summary written to: $summaryPath"
  Write-Step 'Expected final map after restart: COM1, COM2, COM3, COM4.'

  if ($Restart) {
    Write-Step 'Restarting now.'
    shutdown.exe /r /t 0
  } else {
    Write-Step 'Restart skipped. Reboot before final app binding.'
  }
}
finally {
  Stop-Transcript | Out-Null
}
