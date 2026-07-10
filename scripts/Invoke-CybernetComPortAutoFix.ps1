[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$Restart,
  [switch]$Force,
  [string]$EvidenceRoot = 'C:\Temp\CybernetCOM'
)

$ErrorActionPreference = 'Stop'

$script:ComAutoFixPhases = @(
  [pscustomobject]@{ Id = 1; Name = 'Evidence setup'; Percent = 5 },
  [pscustomobject]@{ Id = 2; Name = 'Before-state capture'; Percent = 15 },
  [pscustomobject]@{ Id = 3; Name = 'Eligibility checks'; Percent = 30 },
  [pscustomobject]@{ Id = 4; Name = 'Registry backup'; Percent = 45 },
  [pscustomobject]@{ Id = 5; Name = 'Mapping plan'; Percent = 55 },
  [pscustomobject]@{ Id = 6; Name = 'Apply changes'; Percent = 70 },
  [pscustomobject]@{ Id = 7; Name = 'After-state capture'; Percent = 82 },
  [pscustomobject]@{ Id = 8; Name = 'Summary'; Percent = 92 },
  [pscustomobject]@{ Id = 9; Name = 'Restart'; Percent = 98 }
)

function Test-RunningAsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-ComAutoFixProgress {
  param(
    [int]$Phase,
    [Parameter(Mandatory)][string]$Status,
    [switch]$Completed
  )

  if ($Completed) {
    Write-Progress -Id 156 -Activity 'Cybernet COM AutoFix' -Completed
    Write-Host "[Cybernet COM AutoFix] $Status"
    return
  }

  $phaseInfo = @($script:ComAutoFixPhases | Where-Object { $_.Id -eq $Phase }) | Select-Object -First 1
  $phaseName = if ($phaseInfo) { [string]$phaseInfo.Name } else { 'Working' }
  $percent = if ($phaseInfo) { [int]$phaseInfo.Percent } else { 0 }
  $line = ('Phase {0}/9 - {1}: {2}' -f $Phase, $phaseName, $Status)
  Write-Progress -Id 156 -Activity 'Cybernet COM AutoFix' -Status $line -PercentComplete $percent
  Write-Host "[Cybernet COM AutoFix] $line"
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

function Convert-RegistryProviderPathToNative {
  param([Parameter(Mandatory)][string]$RegistryPath)
  return ($RegistryPath -replace '^HKLM:\\', 'HKLM\')
}

function Initialize-ComAutoFixEvidence {
  param([Parameter(Mandatory)][string]$Root)

  $runStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $runDir = Join-Path $Root "autofix_$runStamp"
  New-Item -ItemType Directory -Path $Root -Force | Out-Null
  New-Item -ItemType Directory -Path $runDir -Force | Out-Null

  return [pscustomobject]@{
    Root = $Root
    RunDir = $runDir
    LogPath = Join-Path $runDir 'autofix-transcript.txt'
    SummaryPath = Join-Path $runDir 'autofix-summary.json'
  }
}

function Get-CybernetComPortState {
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

  $fintekDevices = @($pnp | Where-Object {
    ([string]$_.Name -match 'FINTEK') -or
    ([string]$_.Name -match 'Multi-port serial') -or
    ([string]$_.PNPClass -eq 'MultiPortSerial')
  })

  $sortedPorts = @($ports | Sort-Object CurrentPort)
  return [pscustomobject]@{
    Ports = $sortedPorts
    CurrentPorts = @($sortedPorts | Select-Object -ExpandProperty CurrentPort)
    FintekPresent = $fintekDevices.Count -gt 0
    FintekDevices = $fintekDevices
  }
}

function Test-CybernetComAutoFixEligibility {
  param(
    [Parameter(Mandatory)]$State,
    [bool]$Force
  )

  $currentPorts = @($State.CurrentPorts)
  $currentSet = @($currentPorts | Sort-Object) -join ','
  $alreadyCorrect = ($currentPorts.Count -eq 4 -and $currentSet -eq '1,2,3,4')

  if ($alreadyCorrect) {
    return [pscustomobject]@{ Status = 'already-correct'; Eligible = $false; AlreadyCorrect = $true }
  }

  if (-not $State.FintekPresent -and -not $Force) {
    throw 'FINTEK or multi-port serial device was not detected. Use -Force only if a lead confirms this is still a Cybernet COM repair target.'
  }
  if ($State.Ports.Count -ne 4 -and -not $Force) {
    throw "Expected exactly 4 active Communications Port devices, found $($State.Ports.Count). Use -Force only after a lead confirms the target."
  }
  if ($currentSet -ne '3,4,5,6' -and -not $Force) {
    throw "Expected the known failed map COM3-COM6, found $($currentPorts -join ','). Use -Force only after a lead confirms the target."
  }

  return [pscustomobject]@{ Status = 'eligible'; Eligible = $true; AlreadyCorrect = $false }
}

function Export-ComAutoFixRegistryBackup {
  param(
    [Parameter(Mandatory)]$Ports,
    [Parameter(Mandatory)][string]$RunDir
  )

  $outputPath = Join-Path $RunDir 'reg-export-output.txt'
  $arbiterExportPath = Join-Path $RunDir 'COMNameArbiter-before.reg'
  & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\COM Name Arbiter' $arbiterExportPath /y | Out-File -FilePath $outputPath -Encoding ASCII

  $deviceExports = @()
  $sortedPorts = @($Ports | Sort-Object CurrentPort)
  for ($i = 0; $i -lt $sortedPorts.Count; $i++) {
    $index = $i + 1
    $port = $sortedPorts[$i]
    if (-not (Test-Path -LiteralPath $port.RegistryPath)) {
      throw "Device Parameters registry path not found before backup: $($port.RegistryPath)"
    }

    $deviceExportPath = Join-Path $RunDir ('device-parameters-before-{0:00}.reg' -f $index)
    $nativeRegistryPath = Convert-RegistryProviderPathToNative -RegistryPath $port.RegistryPath
    & reg.exe export $nativeRegistryPath $deviceExportPath /y | Out-File -FilePath $outputPath -Encoding ASCII -Append
    $deviceExports += [pscustomobject]@{
      name = $port.Name
      current_port = ('COM{0}' -f $port.CurrentPort)
      registry_path = $port.RegistryPath
      native_registry_path = $nativeRegistryPath
      export_path = $deviceExportPath
    }
  }

  return [pscustomobject]@{
    com_name_arbiter = $arbiterExportPath
    device_parameters = $deviceExports
  }
}

function New-CybernetComMappingPlan {
  param([Parameter(Mandatory)]$Ports)

  $mapping = @()
  $sortedPorts = @($Ports | Sort-Object CurrentPort)
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
  return @($mapping)
}

function Invoke-CybernetComArbiterReset {
  param([Parameter(Mandatory)][string]$RunDir)

  & reg.exe add 'HKLM\SYSTEM\CurrentControlSet\Control\COM Name Arbiter' /v ComDB /t REG_BINARY /d 0000000000000000000000000000000000000000000000000000000000000000 /f | Out-File -FilePath (Join-Path $RunDir 'reg-reset-output.txt') -Encoding ASCII
}

function Set-CybernetComPortMapping {
  param([Parameter(Mandatory)]$Mapping)

  foreach ($item in $Mapping) {
    if (-not (Test-Path -LiteralPath $item.registry_path)) {
      throw "Device Parameters registry path not found during apply: $($item.registry_path)"
    }
    Write-ComAutoFixProgress -Phase 6 -Status "Assigning $($item.current_port) to $($item.target_port): $($item.name)"
    Set-ItemProperty -LiteralPath $item.registry_path -Name PortName -Value $item.target_port
  }
}

function Write-ComAutoFixSummary {
  param(
    [Parameter(Mandatory)][string]$SummaryPath,
    [Parameter(Mandatory)][string]$Status,
    [Parameter(Mandatory)][string]$RunDir,
    [Parameter(Mandatory)]$State,
    $Mapping,
    $RegistryBackups,
    [bool]$Applied,
    [bool]$RestartRequested,
    [string]$RestartNote
  )

  [pscustomobject]@{
    status = $Status
    evidence_dir = $RunDir
    fintek_present = [bool]$State.FintekPresent
    detected_ports = @($State.CurrentPorts)
    registry_backups = $RegistryBackups
    planned_mapping = if ($Applied) { $null } else { $Mapping }
    applied_mapping = if ($Applied) { $Mapping } else { $null }
    applied = $Applied
    restart_requested = $RestartRequested
    restart_note = $RestartNote
  } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
}

if (-not (Test-RunningAsAdministrator)) {
  throw 'Run this from an elevated Command Prompt or through Run-CybernetComPortAutoFix.cmd.'
}

$evidence = Initialize-ComAutoFixEvidence -Root $EvidenceRoot
Start-Transcript -Path $evidence.LogPath -Force | Out-Null
try {
  Write-ComAutoFixProgress -Phase 1 -Status "Evidence folder: $($evidence.RunDir)"
  hostname | Set-Content -LiteralPath (Join-Path $evidence.RunDir 'hostname.txt') -Encoding ASCII
  Get-Date -Format s | Set-Content -LiteralPath (Join-Path $evidence.RunDir 'started-at.txt') -Encoding ASCII

  Write-ComAutoFixProgress -Phase 2 -Status 'Capturing before-state registry, Ports, MultiPortSerial, and PnP evidence.'
  Invoke-CmdCapture -Command 'reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM' -OutputPath (Join-Path $evidence.RunDir 'serialcomm-before.txt')
  Invoke-CmdCapture -Command 'pnputil /enum-devices /class Ports' -OutputPath (Join-Path $evidence.RunDir 'ports-before.txt')
  Invoke-CmdCapture -Command 'pnputil /enum-devices /class MultiPortSerial' -OutputPath (Join-Path $evidence.RunDir 'multiport-before.txt')
  Get-CimInstance Win32_PnPEntity | Sort-Object Name | Select-Object Name,PNPClass,PNPDeviceID,Status | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence.RunDir 'pnp-before.json') -Encoding UTF8

  Write-ComAutoFixProgress -Phase 3 -Status 'Checking FINTEK presence and COM numbering pattern.'
  $state = Get-CybernetComPortState
  Write-ComAutoFixProgress -Phase 3 -Status "Detected communication ports: $($state.CurrentPorts -join ', ')"
  Write-ComAutoFixProgress -Phase 3 -Status "FINTEK or multi-port serial device present: $($state.FintekPresent)"
  $eligibility = Test-CybernetComAutoFixEligibility -State $state -Force ([bool]$Force)

  if ($eligibility.AlreadyCorrect) {
    Write-ComAutoFixProgress -Phase 7 -Status 'COM ports are already COM1-COM4. Capturing after-state and exiting without changes.'
    Invoke-CmdCapture -Command 'reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM' -OutputPath (Join-Path $evidence.RunDir 'serialcomm-after.txt')
    Invoke-CmdCapture -Command 'pnputil /enum-devices /class Ports' -OutputPath (Join-Path $evidence.RunDir 'ports-after.txt')
    Write-ComAutoFixSummary -SummaryPath $evidence.SummaryPath -Status 'already-correct' -RunDir $evidence.RunDir -State $state -Mapping @() -RegistryBackups $null -Applied $false -RestartRequested $false -RestartNote 'No restart requested because no change was needed.'
    Write-ComAutoFixProgress -Completed -Status "COMPLETE - COM ports already show COM1-COM4. Summary: $($evidence.SummaryPath)"
    return
  }

  Write-ComAutoFixProgress -Phase 4 -Status 'Exporting COM Name Arbiter and active device Device Parameters registry keys.'
  $registryBackups = Export-ComAutoFixRegistryBackup -Ports $state.Ports -RunDir $evidence.RunDir

  Write-ComAutoFixProgress -Phase 5 -Status 'Building COM3-COM6 to COM1-COM4 mapping plan.'
  $mapping = New-CybernetComMappingPlan -Ports $state.Ports
  $mapping | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence.RunDir 'port-mapping-plan.json') -Encoding UTF8

  if (-not $Apply) {
    Write-ComAutoFixProgress -Phase 8 -Status 'Writing dry-run summary. No registry changes were applied.'
    Write-ComAutoFixSummary -SummaryPath $evidence.SummaryPath -Status 'dry-run' -RunDir $evidence.RunDir -State $state -Mapping $mapping -RegistryBackups $registryBackups -Applied $false -RestartRequested $false -RestartNote 'Dry run only. Re-run the apply launcher when ready.'
    Write-ComAutoFixProgress -Completed -Status "DRY RUN COMPLETE - Review $($evidence.SummaryPath), then run Run-CybernetComPortAutoFix.cmd if eligible."
    return
  }

  Write-ComAutoFixProgress -Phase 6 -Status 'Resetting COM Name Arbiter reservation bitmap.'
  Invoke-CybernetComArbiterReset -RunDir $evidence.RunDir
  Set-CybernetComPortMapping -Mapping $mapping

  Write-ComAutoFixProgress -Phase 7 -Status 'Capturing after-state evidence before restart.'
  Invoke-CmdCapture -Command 'reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM' -OutputPath (Join-Path $evidence.RunDir 'serialcomm-after.txt')
  Invoke-CmdCapture -Command 'pnputil /enum-devices /class Ports' -OutputPath (Join-Path $evidence.RunDir 'ports-after.txt')

  $restartNote = if ($Restart) { 'Restart requested by launcher.' } else { 'Restart not requested. Restart manually before final app binding.' }
  Write-ComAutoFixProgress -Phase 8 -Status 'Writing apply summary.'
  Write-ComAutoFixSummary -SummaryPath $evidence.SummaryPath -Status 'applied' -RunDir $evidence.RunDir -State $state -Mapping $mapping -RegistryBackups $registryBackups -Applied $true -RestartRequested ([bool]$Restart) -RestartNote $restartNote

  if ($Restart) {
    Write-ComAutoFixProgress -Phase 9 -Status 'REBOOTING - Expected final map after restart: COM1, COM2, COM3, COM4.'
    shutdown.exe /r /t 0
  } else {
    Write-ComAutoFixProgress -Completed -Status "COMPLETE - Restart skipped. Reboot before final app binding. Summary: $($evidence.SummaryPath)"
  }
}
catch {
  Write-ComAutoFixProgress -Completed -Status "FAILED - $($_.Exception.Message)"
  throw
}
finally {
  Stop-Transcript | Out-Null
}
