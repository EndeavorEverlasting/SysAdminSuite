[CmdletBinding()]
param()

$runningOnWindows = if ($PSVersionTable.PSVersion.Major -ge 6) { $IsWindows } else { $env:OS -eq 'Windows_NT' }
if (-not $runningOnWindows) { throw 'This GUI is supported on Windows only.' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
  if ($PSCommandPath) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") | Out-Null
    return
  }
  throw 'Relaunch this GUI in STA mode.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'Utilities\Invoke-RunControl.ps1')
. (Join-Path $repoRoot 'Utilities\Invoke-UndoRedo.ps1')
$kronosScript = Join-Path $repoRoot 'GetInfo\Get-KronosClockInfo.ps1'
$workerScript = Join-Path $repoRoot 'Mapping\Workers\Map-MachineWide.ps1'
$controllerScript = Join-Path $repoRoot 'Mapping\Controllers\Map-Run-Controller.ps1'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Format-ObjectText {
  param([object]$InputObject)
  if ($null -eq $InputObject) { return 'No data loaded.' }
  if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
    $items = @($InputObject)
    if (-not $items.Count) { return 'No data loaded.' }
    $props = @($items[0].PSObject.Properties.Name)
    if ($props -contains 'QueryInput') {
      return (($items | Select-Object QueryInput,IPAddress,HostName,DeviceName,MACAddress,SerialNumber,Model,Reachable | Format-Table -AutoSize | Out-String).Trim())
    }
    return (($items | Format-Table -AutoSize | Out-String).Trim())
  }
  return (($InputObject | ConvertTo-Json -Depth 8) | Out-String).Trim()
}

function Format-UndoRedoText {
  param([psobject]$Session)
  if (-not $Session) { return 'No undo/redo session loaded.' }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("Imported From: $($Session.ImportedFromPath)")
  $lines.Add("Undo: $($Session.UndoStack.Count) | Redo: $($Session.RedoStack.Count) | History: $($Session.History.Count)")
  if ($Session.UndoStack.Count) {
    $topUndo = $Session.UndoStack[$Session.UndoStack.Count - 1]
    $lines.Add("Top Undo: $($topUndo.Name) -> $($topUndo.Target)")
  }
  if ($Session.RedoStack.Count) {
    $topRedo = $Session.RedoStack[$Session.RedoStack.Count - 1]
    $lines.Add("Top Redo: $($topRedo.Name) -> $($topRedo.Target)")
  }
  if ($Session.History.Count) {
    $lines.Add('')
    $lines.Add('History:')
    foreach ($item in $Session.History) {
      $lines.Add(("[{0}] {1} :: {2} -> {3}" -f $item.Timestamp, $item.Event, $item.Name, $item.Target))
    }
  }
  return ($lines -join [Environment]::NewLine)
}

function ConvertTo-SingleQuotedPowerShellLiteral {
  param([AllowNull()][string]$Value)
  if ($null -eq $Value) { return "''" }
  return "'{0}'" -f ($Value -replace "'", "''")
}

function Get-TrimmedLines {
  param([string[]]$Lines)
  return @($Lines | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
}

function Set-StatusBarText {
  param(
    [string]$Message,
    [string]$Category = 'Ready'
  )

  if ($script:StatusCategoryLabel) { $script:StatusCategoryLabel.Text = $Category }
  if ($script:StatusMessageLabel) { $script:StatusMessageLabel.Text = if ($Message) { $Message } else { '' } }
}

function Copy-TextToClipboard {
  param(
    [string]$Value,
    [string]$Label = 'Text'
  )

  if ([string]::IsNullOrWhiteSpace($Value)) { throw "There is no $Label to copy yet." }
  [System.Windows.Forms.Clipboard]::SetText($Value)
  Set-StatusBarText -Category 'Copied' -Message "$Label copied to the clipboard."
}

function Get-CurrentSessionRoot {
  if ($script:LastRunSession -and $script:LastRunSession.Root -and (Test-Path -LiteralPath $script:LastRunSession.Root)) {
    return $script:LastRunSession.Root
  }

  foreach ($control in @($txtStop,$txtStatus,$txtUndo)) {
    if (-not $control -or [string]::IsNullOrWhiteSpace($control.Text)) { continue }
    $candidateRoot = Split-Path -Parent $control.Text
    if ($candidateRoot -and (Test-Path -LiteralPath $candidateRoot)) { return $candidateRoot }
  }

  return $null
}

function Open-RunSessionFolder {
  $sessionRoot = Get-CurrentSessionRoot
  if (-not $sessionRoot) { throw 'Launch or load a run session first.' }

  Start-Process -FilePath 'explorer.exe' -ArgumentList @($sessionRoot) | Out-Null
  Set-StatusBarText -Category 'Opened' -Message "Opened session folder: $sessionRoot"
}

function Show-BrowseFileDialog {
  param(
    [string]$Title = 'Select a file',
    [string]$Filter = 'JSON files (*.json)|*.json|CSV files (*.csv)|*.csv|All files (*.*)|*.*',
    [string]$InitialDirectory
  )
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Title = $Title
  $dlg.Filter = $Filter
  if ($InitialDirectory -and (Test-Path -LiteralPath $InitialDirectory)) { $dlg.InitialDirectory = $InitialDirectory }
  if ($dlg.ShowDialog() -eq 'OK') { return $dlg.FileName }
  return $null
}

function Show-BrowseFolderDialog {
  param([string]$Description = 'Select a folder')
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = $Description
  $dlg.ShowNewFolderButton = $true
  if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
  return $null
}

function Update-RunActionState {
  if (-not $btnStop) { return }

  $btnStop.Enabled = [bool]($txtStop -and -not [string]::IsNullOrWhiteSpace($txtStop.Text))
  $btnOpenSession.Enabled = [bool](Get-CurrentSessionRoot)
  $btnCopyStatus.Enabled = [bool]($txtStatusView -and -not [string]::IsNullOrWhiteSpace($txtStatusView.Text))
  $btnCopyHistory.Enabled = [bool]($txtHistoryView -and -not [string]::IsNullOrWhiteSpace($txtHistoryView.Text))

  $hasUndo = [bool]($script:LoadedSession -and $script:LoadedSession.UndoStack -and $script:LoadedSession.UndoStack.Count -gt 0)
  $hasRedo = [bool]($script:LoadedSession -and $script:LoadedSession.RedoStack -and $script:LoadedSession.RedoStack.Count -gt 0)
  $btnUndo.Enabled = $hasUndo
  $btnRedo.Enabled = $hasRedo
}

function Build-WorkerOptionsString {
  $parts = @()
  switch ($cmbRunMode.SelectedItem) {
    'Recon Only (-ListOnly)'     { $parts += '-ListOnly' }
    'Plan Only (-PlanOnly)'      { $parts += '-PlanOnly' }
    'Full Run + Prune'           { $parts += '-PruneNotInList' }
  }
  if ($chkPreflight.Checked)       { $parts += '-Preflight' }
  if ($chkRestartSpooler.Checked)  { $parts += '-RestartSpoolerIfNeeded' }
  $queues = @($txtQueuesAdd.Text -split '[,;\r\n]+' | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
  if ($queues.Count) {
    $qLiterals = ($queues | ForEach-Object { "'{0}'" -f ($_ -replace "'","''") }) -join ','
    $parts += "-Queues $qLiterals"
  }
  $remove = @($txtQueuesRemove.Text -split '[,;\r\n]+' | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
  if ($remove.Count) {
    $rLiterals = ($remove | ForEach-Object { "'{0}'" -f ($_ -replace "'","''") }) -join ','
    $parts += "-RemoveQueues $rLiterals"
  }
  $defQ = $txtDefaultQueue.Text.Trim()
  if ($defQ) { $parts += "-DefaultQueue '{0}'" -f ($defQ -replace "'","''") }
  $txtWorkerOptions.Text = $parts -join ' '
}

function Load-SafeWorkerExample {
  $cmbRunMode.SelectedIndex = 0
  $chkPreflight.Checked = $true
  $chkRestartSpooler.Checked = $false
  $txtQueuesAdd.Text = "\\PRINTSRV\Q01`r`n\\PRINTSRV\Q02"
  $txtQueuesRemove.Text = ''
  $txtDefaultQueue.Text = ''
  Build-WorkerOptionsString
  Set-StatusBarText -Category 'Template' -Message 'Loaded a safe worker example that favors review before change.'
}

function New-GuiRunSession {
  param([ValidateSet('Worker','Controller')][string]$Kind)

  $sessionRoot = Join-Path $repoRoot (Join-Path 'Mapping\Output\GuiRuns' ('{0}-{1}' -f $Kind, (Get-Date -Format 'yyyyMMdd-HHmmss')))
  New-Item -ItemType Directory -Force -Path $sessionRoot | Out-Null

  [pscustomobject]@{
    Kind     = $Kind
    Root     = $sessionRoot
    Stop     = Join-Path $sessionRoot 'Stop.json'
    Status   = Join-Path $sessionRoot ($(if ($Kind -eq 'Controller') { 'Controller.Status.json' } else { 'Worker.Status.json' }))
    Undo     = Join-Path $sessionRoot ($(if ($Kind -eq 'Controller') { 'UndoRedo.Controller.json' } else { 'UndoRedo.Worker.json' }))
    Launcher = Join-Path $sessionRoot ('Start-{0}.ps1' -f $Kind)
  }
}

function Refresh-RunStatusView {
  if (-not $txtStatus.Text -or -not (Test-Path -LiteralPath $txtStatus.Text)) {
    $txtStatusView.Text = 'Status file not found yet. Launch a run or wait for the worker/controller to publish status.'
    Set-StatusBarText -Category 'Waiting' -Message 'Status file not found yet.'
    Update-RunActionState
    return
  }

  try {
    $snapshot = Import-RunStatusSnapshot -Path $txtStatus.Text
    $statusText = Format-ObjectText $snapshot

    # When the run is finished, append an artifact summary so users know exactly where the output landed.
    $finished = $snapshot.State -in @('Completed','Stopped','Error','Failed')
    if ($finished -and $snapshot.Data) {
      $d = $snapshot.Data
      $artifactLines = @()
      $artifactLines += ''
      $artifactLines += '--- Artifacts ---'
      if ($d.OutputDirectory -and (Test-Path -LiteralPath $d.OutputDirectory)) {
        $artifactLines += "  Folder:      $($d.OutputDirectory)"
        $files = Get-ChildItem -LiteralPath $d.OutputDirectory -File -ErrorAction SilentlyContinue
        foreach ($f in $files) { $artifactLines += "    $($f.Name)  ($([math]::Round($f.Length/1KB,1)) KB)" }
      } elseif ($d.OutputRoot) {
        $artifactLines += "  Output root: $($d.OutputRoot)"
      }
      if ($d.ResultsPath -and (Test-Path -LiteralPath $d.ResultsPath)) {
        $artifactLines += "  Results CSV: $($d.ResultsPath)"
      }
      if ($d.HtmlPath -and (Test-Path -LiteralPath $d.HtmlPath)) {
        $artifactLines += "  HTML Report: $($d.HtmlPath)"
      }
      $artifactLines += ''
      $artifactLines += 'Click  Open Session Folder  to view these files.'
      $statusText += [Environment]::NewLine + ($artifactLines -join [Environment]::NewLine)
    }

    $txtStatusView.Text = $statusText
    if ($finished) {
      Set-StatusBarText -Category 'Done' -Message "Run $($snapshot.State). Artifacts ready -- click Open Session Folder."
    } else {
      Set-StatusBarText -Category 'Refreshed' -Message "Loaded status snapshot from $($txtStatus.Text)"
    }
  } catch {
    $txtStatusView.Text = $_.Exception.Message
    Set-StatusBarText -Category 'Error' -Message 'Failed to load the status snapshot.'
  }

  Update-RunActionState
}

function Refresh-RunHistoryView {
  if (-not $txtUndo.Text -or -not (Test-Path -LiteralPath $txtUndo.Text)) {
    $txtHistoryView.Text = 'Undo/redo history not found yet. Launch a run or load a session history file first.'
    Set-StatusBarText -Category 'Waiting' -Message 'Undo/redo history file not found yet.'
    Update-RunActionState
    return
  }

  try {
    $script:LoadedSession = Import-UndoRedoSession -Path $txtUndo.Text
    $txtHistoryView.Text = Format-UndoRedoText $script:LoadedSession
    Set-StatusBarText -Category 'Loaded' -Message "Loaded undo/redo history from $($txtUndo.Text)"
  } catch {
    $txtHistoryView.Text = $_.Exception.Message
    Set-StatusBarText -Category 'Error' -Message 'Failed to load the undo/redo session.'
  }

  Update-RunActionState
}

function Start-GuiRun {
  param([ValidateSet('Worker','Controller')][string]$Mode)

  Set-StatusBarText -Category 'Launching' -Message "Preparing $Mode run..."
  if (-not (Test-Path -LiteralPath $workerScript)) { throw "Worker script not found: $workerScript" }
  if ($Mode -eq 'Controller' -and -not (Test-Path -LiteralPath $controllerScript)) { throw "Controller script not found: $controllerScript" }

  $session = New-GuiRunSession -Kind $Mode
  $workerOptions = if ($txtWorkerOptions.Text) { $txtWorkerOptions.Text.Trim() } else { '' }

  if ($Mode -eq 'Controller') {
    $targets = Get-TrimmedLines -Lines $txtRunTargets.Lines
    if (-not $targets.Count) { throw 'Enter at least one controller target.' }
    $targetLiteral = ($targets | ForEach-Object { ConvertTo-SingleQuotedPowerShellLiteral -Value $_ }) -join ','
    $launchCommand = @(
      '& ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $controllerScript),
      '-Computers ' + $targetLiteral,
      '-LocalScriptPath ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $workerScript),
      '-SessionRoot ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $session.Root),
      '-StopSignalPath ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $session.Stop),
      '-StatusPath ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $session.Status),
      '-EnableUndoRedo',
      '-UndoRedoLogPath ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $session.Undo)
    ) -join ' '
    if ($workerOptions) {
      $launchCommand += ' -WorkerArgumentLine ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $workerOptions)
    }
  } else {
    $launchCommand = @(
      '& ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $workerScript),
      '-StopSignalPath ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $session.Stop),
      '-StatusPath ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $session.Status),
      '-EnableUndoRedo',
      '-UndoRedoLogPath ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $session.Undo),
      '-OutputRoot ' + (ConvertTo-SingleQuotedPowerShellLiteral -Value $session.Root)
    ) -join ' '
    if ($workerOptions) {
      $launchCommand += ' ' + $workerOptions
    }
  }

  $launcherContent = @(
    '$ErrorActionPreference = ''Stop''',
    $launchCommand
  ) -join [Environment]::NewLine

  Set-Content -LiteralPath $session.Launcher -Value $launcherContent -Encoding UTF8
  $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$session.Launcher) -PassThru -WindowStyle Minimized

  $txtStop.Text = $session.Stop
  $txtStatus.Text = $session.Status
  $txtUndo.Text = $session.Undo
  $script:LoadedSession = $null
  $script:LastRunSession = $session
  $txtHistoryView.Text = 'Waiting for undo/redo history...'
  $txtStatusView.Text = (@(
    "Started $Mode run.",
    "PID: $($proc.Id)",
    "Session root: $($session.Root)",
    "Launcher: $($session.Launcher)",
    ('Worker options: {0}' -f $(if ($workerOptions) { $workerOptions } else { '<none>' }))
  ) -join [Environment]::NewLine)

  Set-StatusBarText -Category 'Started' -Message "$Mode run launched successfully. Monitoring session output now."
  Update-RunActionState
}

# -- Tutorial System -- Menu-Based Tracks --
# Each track is a short, focused walkthrough (3-6 steps) for a specific use case.
# The menu screen lets the user pick which track to follow.
# Architecture note for future contributors:
#   - To add a new track, add an entry to $script:TutorialTracks and a matching step array.
#   - Each step has: Title, Body, Highlights (array of control variable names).
#   - The menu rebuilds automatically from $script:TutorialTracks.

$script:TutorialTracks = [ordered]@{
  'PrinterLayout' = @{
    Label = [char]0x2637 + '  Printer Layout (Recon)'
    Desc  = 'See what printers are on a PC before mapping'
    Color = [System.Drawing.Color]::FromArgb(100,60,150)
    Steps = @(
      @{ Title = 'Printer Layout: What Is It?'; Highlights = @(); Body = "Before you map new printers, you need to know what is already there.`n`nPrinter Layout = running a Recon Only scan to list every printer (UNC network queues and local printers) on a machine.`n`nThis is the safest first step before any mapping changes." }
      @{ Title = 'Printer Layout: Load and Run Recon'; Highlights = @('btnExampleOptions','btnStartWorker'); Body = "1. Click Load Safe Example (or Ctrl+E) to pre-fill Recon mode`n2. Click the big green START Local Worker button`n3. Confirm with Yes`n`nThis snapshots your printers without changing anything." }
      @{ Title = 'Printer Layout: Read the Layout'; Highlights = @('btnOpenSession'); Body = "Click Open Session Folder and open Results.csv or Results.html.`n`nYou will see every printer on this machine:`n`n  Type   Target                        Status`n  UNC    \\\\printsrv\\lobby-hp4050      PresentNow`n  UNC    \\\\printsrv\\office-hp5550     PresentNow`n  LOCAL  Microsoft Print to PDF        PresentNow`n  LOCAL  Fax                           PresentNow`n`nThis is your baseline. Use it to decide what to add or remove." }
      @{ Title = 'Printer Layout: Done!'; Highlights = @(); Body = "You now have a complete printer inventory for this machine!`n`nFor other PCs: type their hostnames in Controller Targets, then use Start Controller with Recon Only mode.`n`nThe Results.csv from each host tells you exactly what is mapped before you make changes.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'PrinterMapping' = @{
    Label = [char]0x2399 + '  Printer Mapping'
    Desc  = 'Map or remove printers across workstations'
    Color = [System.Drawing.Color]::FromArgb(30,150,30)
    Steps = @(
      @{ Title = 'Printer Mapping: Load a Safe Example'; Highlights = @('btnExampleOptions'); Body = "Let's do a safe dry run right now.`n`nClick the highlighted Load Safe Example button (or press Ctrl+E).`n`nThis pre-fills Recon Only + Preflight mode, which takes a snapshot of your existing printers without making any changes. Completely safe on production machines.`n`nClick it now, then press Next." }
      @{ Title = 'Printer Mapping: Hit the Green GO Button'; Highlights = @('btnStartWorker'); Body = "Now click the big green START Local Worker button at the bottom.`n`nThis runs a Recon scan on THIS machine only:`n- Reads your current printers`n- Writes Results.csv and Results.html`n- Makes ZERO changes`n`nA confirmation dialog will appear -- click Yes.`nIf anything goes wrong, the big red STOP button at the top right stops it immediately." }
      @{ Title = 'Printer Mapping: Check Your Output'; Highlights = @('txtStatusView','btnOpenSession'); Body = "Look at the Status pane below. It should say Completed.`n`nClick Open Session Folder to see what was created:`n`n  Run.log        - full transcript`n  Preflight.csv  - printers before changes`n  Results.csv    - final state`n  Results.html   - visual report`n`nOpen Results.html in a browser for a quick audit." }
      @{ Title = 'Example: What Success Looks Like'; Highlights = @('txtStatusView'); Body = "The Status pane shows something like:`n`n  {`n    ""State"":  ""Completed"",`n    ""Stage"":  ""ListOnly"",`n    ""Message"": ""ListOnly inventory completed.""`n  }`n`nAnd Results.csv has rows like:`n`n  Type   Target                     Status`n  UNC    \\\\printsrv\\lobby-hp4050   PresentBefore`n  LOCAL  Microsoft Print to PDF     PresentAfter`n`nTo actually map printers, switch Run Mode to Full Run and add queue paths in Queues to Add." }
      @{ Title = 'Printer Mapping: Done!'; Highlights = @(); Body = "You just completed a Printer Mapping recon!`n`nNext steps for real work:`n1. Change Run Mode to Full Run`n2. Type queue paths in Queues to Add (e.g. \\\\PRINTSRV\\Lobby-HP4050)`n3. For multiple PCs, type hostnames in Controller Targets and use Start Controller`n`nAlways Recon first, review, then Full Run.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'KronosClock' = @{
    Label = [char]0x23F0 + '  Kronos Clock'
    Desc  = 'Probe network clocks for MAC, serial, model'
    Color = [System.Drawing.Color]::FromArgb(0,120,180)
    Steps = @(
      @{ Title = 'Kronos: Switch to the Kronos Tab'; Highlights = @(); Body = "Click the Kronos Lookup tab at the top of the window.`n`nThis tab lets you probe network time clocks (Kronos, UKG, etc.) to collect their MAC address, serial number, model, and hostname.`n`nSwitch to that tab now, then press Next." }
      @{ Title = 'Kronos: Enter a Target and Probe'; Highlights = @('txtTargets','btnProbe'); Body = "In the Targets box, type an IP address or hostname of a clock.`nExample: 10.1.2.50`n`nThen click Probe Targets. The tool will scan via ICMP, SNMP, ARP, HTTP, and DNS to collect identity info.`n`nIf you do not have a real clock handy, type any IP -- the probe will report Reachable=False, which is still useful to see." }
      @{ Title = 'Kronos: Read the Results'; Highlights = @('txtClockResults','btnCopyClockResults'); Body = "The Results pane shows a table like:`n`n  QueryInput  IPAddress   HostName       MAC               Serial  Reachable`n  10.1.2.50   10.1.2.50   KRON-CLK-01    00:1A:2B:3C:4D:5E KRN4401 True`n`nClick Copy Results to paste into a ticket or DHCP form.`nThe Output CSV is also saved to disk for Excel." }
      @{ Title = 'Kronos: Search a Saved Inventory'; Highlights = @('btnInventory','cmbLookup','txtLookup','btnFind'); Body = "Already have a saved CSV? Click Load Inventory to import it.`n`nTo search:`n1. Pick a field: IP, MAC, Serial, HostName, or Any`n2. Type a value in the search box`n3. Click Find Match`n`nThis is the cross-lookup workflow: start with one identifier and get back the full record." }
      @{ Title = 'Kronos: Done!'; Highlights = @(); Body = "You now know how to probe clocks and search inventories!`n`nTip: Save the Output CSV after each probe. You can re-import it later without re-probing the network.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'NeuronMachineInfo' = @{
    Label = [char]0x2328 + '  Neuron MachineInfo'
    Desc  = 'Get serial, IP, MAC for Neuron workstations'
    Color = [System.Drawing.Color]::FromArgb(120,80,180)
    Steps = @(
      @{ Title = 'Neuron MachineInfo: Overview'; Highlights = @(); Body = "Get-MachineInfo.ps1 queries workstations via WMI to collect:`n- Serial number (BIOS)`n- IP address and MAC address`n- Monitor serial numbers`n`nYou can run this directly from the Machine Info tab in this GUI.`nNo command line needed!" }
      @{ Title = 'Neuron MachineInfo: Switch to Machine Info Tab'; Highlights = @('txtMITargets','cmbMIMode'); Body = "Click the Machine Info tab at the top of the window.`n`nMake sure the Script dropdown is set to:`n  Get-MachineInfo  (workstation serial/IP/MAC)`n`nThen type your Neuron hostnames in the Targets box, one per line:`n  NEURON-WKS001`n  NEURON-WKS002`n  NEURON-WKS003`n`nOr click the [...] next to Host List File to load a .txt file." }
      @{ Title = 'Neuron MachineInfo: Run the Probe'; Highlights = @('btnMIRun','txtMIOutCsv'); Body = "Set the Output CSV path (a default is pre-filled).`nAdjust Throttle if you have many hosts (default: 15 at a time).`n`nClick the Run Probe button.`n`nThe script queries each host in parallel and writes the CSV.`nResults appear in the pane below, and the Output Artifacts bar shows the file path and size." }
      @{ Title = 'Example: MachineInfo Output'; Highlights = @('txtMIResults'); Body = "The output CSV has these columns:`n`n  Timestamp | HostName | Serial | IPAddress | MACAddress | MonitorSerials | Status`n`n  2026-03-24  NEURON-WKS001  5CG123  10.1.5.20  AA:BB:CC:DD:EE:FF  SN12345  OK`n  2026-03-24  NEURON-WKS002  Offline                                          Offline`n`nClick Copy Results to paste into a ticket, or Open Output Folder to find the CSV.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'PrinterMachineInfo' = @{
    Label = [char]0x2316 + '  Printer MachineInfo'
    Desc  = 'Get MAC and serial from network printers'
    Color = [System.Drawing.Color]::FromArgb(180,100,30)
    Steps = @(
      @{ Title = 'Printer MachineInfo: Overview'; Highlights = @(); Body = "Get-PrinterMacSerial.ps1 probes network printers to collect:`n- MAC address (SNMP, HTTP, ARP)`n- Serial number (SNMP, HTTP scrape)`n`nUseful for asset tagging, warranty lookups, and DHCP reservations.`nRun this from the Machine Info tab. No command line needed." }
      @{ Title = 'Printer MachineInfo: Switch to Machine Info Tab'; Highlights = @('txtMITargets','cmbMIMode'); Body = "Click the Machine Info tab at the top.`n`nChange the Script dropdown to:`n  Get-PrinterMacSerial  (printer MAC/serial via SNMP)`n`nType printer IPs in the Targets box:`n  10.1.3.100`n  10.1.3.101`n`nOr click [...] next to Host List File to load a text file of IPs." }
      @{ Title = 'Printer MachineInfo: Run and Review'; Highlights = @('btnMIRun','txtMIResults'); Body = "Click Run Probe. The script tries SNMP first, then HTTP scraping, then ARP as a fallback.`n`nResults appear in the pane below and the CSV is saved to the Output CSV path.`n`nThe Output Artifacts bar shows exactly where the file landed and its size." }
      @{ Title = 'Example: Printer MachineInfo Output'; Highlights = @('txtMIResults'); Body = "The output CSV has these columns:`n`n  IP | Status | MAC | Serial | Source | Notes`n`n  10.1.3.100  Online   AA:BB:CC:DD:EE:FF  VNB1234567  SNMP serial + SNMP MAC`n  10.1.3.101  Online   11:22:33:44:55:66  (none)      SNMP MAC; Serial unavailable`n  10.1.3.102  Offline  (none)             (none)      Host unreachable (ICMP)`n`nClick Copy Results or Open Output Folder for the CSV.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'CybernetMachineInfo' = @{
    Label = [char]0x2395 + '  Cybernet / Workstation Info'
    Desc  = 'Get serial, IP, MAC for Cybernet PCs'
    Color = [System.Drawing.Color]::FromArgb(50,130,130)
    Steps = @(
      @{ Title = 'Cybernet MachineInfo: Overview'; Highlights = @(); Body = "This uses the same Get-MachineInfo.ps1 script as Neuron, but for Cybernet or any Windows workstation.`n`nIt collects: Serial, IP, MAC, and Monitor Serials via WMI.`n`nThe only difference is the host list you provide." }
      @{ Title = 'Cybernet MachineInfo: Use the Machine Info Tab'; Highlights = @('txtMITargets','cmbMIMode'); Body = "Click the Machine Info tab. Make sure the Script dropdown is set to:`n  Get-MachineInfo  (workstation serial/IP/MAC)`n`nType Cybernet hostnames in the Targets box:`n  CYBER-WKS001`n  CYBER-WKS002`n`nOr load a host list file using the [...] button.`n`nTip: Increase Throttle to 30 for large lists." }
      @{ Title = 'Cybernet MachineInfo: Run and Review'; Highlights = @('btnMIRun','txtMIResults'); Body = "Click Run Probe. Results appear in the pane below.`n`nOutput CSV columns:`n`n  Timestamp | HostName | Serial | IPAddress | MACAddress | MonitorSerials | Status`n`n  2026-03-24  CYBER-WKS001  MXL987  10.2.1.10  AA:BB:CC:DD:EE:FF  MON-SN1  OK`n  2026-03-24  CYBER-WKS002  MXL988  10.2.1.11  11:22:33:44:55:66  MON-SN2  OK`n`nClick Copy Results or Open Output Folder.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'RepoHealth' = @{
    Label = [char]0x2692 + '  Repo File Health'
    Desc  = 'Fix BOM, encoding, locks, and line endings'
    Color = [System.Drawing.Color]::FromArgb(60,140,100)
    Steps = @(
      @{ Title = 'Repo Health: Why It Matters'; Highlights = @(); Body = "PowerShell 5.1 cannot parse scripts with non-ASCII characters (em-dashes, checkmarks, box-drawing) unless the file has a UTF-8 BOM (Byte Order Mark).`n`nDownloaded files may also have Zone.Identifier locks that block execution.`n`nThe tools/ folder has three utilities to keep the repo healthy:`n  - Invoke-RepoFileHealth.ps1  (all-in-one)`n  - Add-Utf8Bom.ps1            (BOM only)`n  - Test-ScriptHealth.ps1      (validation)" }
      @{ Title = 'Repo Health: Dry-Run First'; Highlights = @(); Body = "Open a PowerShell terminal and run:`n`n  .\\tools\\Invoke-RepoFileHealth.ps1`n`nThis is a DRY-RUN by default. It scans every file and reports:`n  - Missing UTF-8 BOM`n  - Zone.Identifier locks`n  - Wrong line endings`n  - Non-ASCII characters that may break PS 5.1`n`nNo files are changed until you add -Fix." }
      @{ Title = 'Repo Health: Apply Fixes'; Highlights = @(); Body = "When you are ready, run:`n`n  .\\tools\\Invoke-RepoFileHealth.ps1 -Fix`n`nThis will:`n  1. Remove Zone.Identifier locks (unblock files)`n  2. Add UTF-8 BOM to .ps1, .psm1, .psd1, .csv files`n  3. Normalize line endings to CRLF`n`nFor BOM-only fixes:`n  .\\tools\\Add-Utf8Bom.ps1 -Fix`n`nTo validate without fixing:`n  .\\tools\\Test-ScriptHealth.ps1" }
      @{ Title = 'Repo Health: Done!'; Highlights = @(); Body = "Run these tools after pulling new code or adding scripts.`n`nTip: Add Test-ScriptHealth.ps1 to your CI pipeline to catch encoding issues before they break PS 5.1 users.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'SoftwareInventory' = @{
    Label = [char]0x2630 + '  Software Inventory'
    Desc  = 'Audit installed software across machines'
    Color = [System.Drawing.Color]::FromArgb(140,100,40)
    Steps = @(
      @{ Title = 'Software Inventory: Overview'; Highlights = @(); Body = "Config\\Inventory-Software.ps1 collects installed software from workstations and builds a superset CSV.`n`nUse it to:`n  - Audit what is installed before a migration`n  - Compare machines for consistency`n  - Feed into Runbook-Inventory.ps1 for go-live checklists" }
      @{ Title = 'Software Inventory: Run It'; Highlights = @(); Body = "Open a PowerShell terminal and run:`n`n  .\\Config\\Inventory-Software.ps1`n`nThe script queries Win32_Product via WMI on each target and writes a CSV.`n`nFor a dry run (plan only):`n  .\\Config\\Inventory-Software.ps1 -WhatIf`n`nOutput lands in the Config\\Output folder by default." }
      @{ Title = 'Software Inventory: Review Output'; Highlights = @(); Body = "The output CSV contains:`n`n  HostName | Name | Version | Vendor | InstallDate`n`nOpen it in Excel or import with:`n  Import-Csv .\\Config\\Output\\software_superset.csv`n`nUse Runbook-Inventory.ps1 to cross-check against your expected software list.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'NetworkTest' = @{
    Label = [char]0x2301 + '  Network Testing'
    Desc  = 'Test connectivity, DNS, and ports'
    Color = [System.Drawing.Color]::FromArgb(40,100,160)
    Steps = @(
      @{ Title = 'Network Test: Overview'; Highlights = @(); Body = "Utilities\\Test-Network.ps1 is a quick connectivity checker.`n`nIt tests:`n  - ICMP ping (reachability)`n  - DNS resolution`n  - TCP port connectivity`n`nUseful before running probes or mapping to verify the network path is clear." }
      @{ Title = 'Network Test: Run It'; Highlights = @(); Body = "Open a PowerShell terminal and run:`n`n  .\\Utilities\\Test-Network.ps1 -ComputerName 10.1.2.50`n`nOr test multiple hosts:`n  .\\Utilities\\Test-Network.ps1 -ComputerName '10.1.2.50','10.1.2.51'`n`nThe output shows reachability, latency, and DNS results for each target." }
      @{ Title = 'Network Test: Done!'; Highlights = @(); Body = "Run this before any probe or mapping job to verify connectivity.`n`nTip: Pipe the output to Export-Csv for a record:`n  .\\Utilities\\Test-Network.ps1 -ComputerName (Get-Content hosts.txt) | Export-Csv net-check.csv`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'ADPrintingGroup' = @{
    Label = [char]0x2318 + '  AD Printing Group'
    Desc  = 'Add computers to AD printing security groups'
    Color = [System.Drawing.Color]::FromArgb(160,60,60)
    Steps = @(
      @{ Title = 'AD Printing Group: Overview'; Highlights = @(); Body = "ActiveDirectory\\Add-Computers-To-PrintingGroup.ps1 bulk-adds computer accounts to an AD security group used for printer deployment.`n`nIt supports:`n  - -PlanOnly mode (writes artifacts, touches nothing in AD)`n  - Logging of every action`n  - Reading targets from a hosts.txt file" }
      @{ Title = 'AD Printing Group: Plan First'; Highlights = @(); Body = "Always start with a plan:`n`n  .\\ActiveDirectory\\Add-Computers-To-PrintingGroup.ps1 -PlanOnly`n`nThis reads ActiveDirectory\\hosts.txt and reports which machines would be added to the group, without making changes.`n`nReview the plan output before proceeding." }
      @{ Title = 'AD Printing Group: Apply'; Highlights = @(); Body = "When the plan looks correct:`n`n  .\\ActiveDirectory\\Add-Computers-To-PrintingGroup.ps1`n`nThe script adds each computer from hosts.txt to the target AD group and logs every action.`n`nRequires: AD PowerShell module and appropriate permissions.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'PSVersionPivot' = @{
    Label = [char]0x21C4 + '  PS Version Pivot'
    Desc  = 'How tools handle PS 5.1 vs PS 7 differences'
    Color = [System.Drawing.Color]::FromArgb(100,100,100)
    Steps = @(
      @{ Title = 'PS Version Pivot: The Problem'; Highlights = @(); Body = "Some features need PowerShell 7 (pwsh), others need 5.1 (powershell.exe).`n`nExamples:`n  - PS 5.1: WMI cmdlets (Get-WmiObject), some AD modules`n  - PS 7: Parallel ForEach, newer .NET APIs, better JSON handling`n`nIf a script runs on the wrong version, it may fail silently or crash." }
      @{ Title = 'PS Version Pivot: The Solution'; Highlights = @(); Body = "The suite includes tools\\Resolve-PSRuntime.ps1.`n`nDot-source it at the top of any script:`n`n  . `"$PSScriptRoot\\..\\tools\\Resolve-PSRuntime.ps1`"`n`nIt exposes:`n  `$PSRuntimeIs5  -- true on Windows PowerShell`n  `$PSRuntimeIs7  -- true on PowerShell 7+`n  Invoke-PSPivot  -- re-launches the script on the required engine`n`nWhen a pivot occurs, it logs the transition in magenta so you know exactly what happened." }
      @{ Title = 'PS Version Pivot: Example'; Highlights = @(); Body = "In your script:`n`n  . `"$PSScriptRoot\\..\\tools\\Resolve-PSRuntime.ps1`"`n  if (`$PSRuntimeIs5 -and `$needsPS7) {`n      Invoke-PSPivot -RequiredVersion 7 ``\n          -ScriptPath `$PSCommandPath ``\n          -Arguments `$PSBoundParameters`n  }`n`nThe user sees:`n  [Resolve-PSRuntime] PIVOT: PS 5 -> PS 7 | Script: ...`n`nAnd the script continues on the correct engine.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'GoLivePipeline' = @{
    Label = [char]0x2692 + '  Go-Live Pipeline'
    Desc  = 'Fetch installers, stage to clients, run preflight'
    Color = [System.Drawing.Color]::FromArgb(180,50,50)
    Steps = @(
      @{ Title = 'Go-Live Pipeline: Overview'; Highlights = @(); Body = "The Config folder contains a full go-live pipeline:`n`n  GoLiveTools.ps1       -- shared cmdlets (fetch, hash, stage)`n  Fetch-Cycle.ps1       -- rebuild + test + fetch + hash`n  Fetch-Installers.ps1  -- download installers from sources.csv`n  Stage-To-Clients.ps1  -- robocopy repo to client PCs`n  Run-Preflight.ps1     -- pre-deployment checks`n  Runbook-Inventory.ps1 -- cross-check installed vs expected`n`nRequires PowerShell 7+ for parallel fetch." }
      @{ Title = 'Go-Live Pipeline: Fetch Cycle'; Highlights = @(); Body = "The main entry point is:`n`n  .\\Config\\Fetch-Cycle.ps1`n`nThis runs the full pipeline in order:`n  1. Preflight-Repo   (validate repo structure)`n  2. Rebuild-FetchMap (build fetch-map.csv from sources.csv)`n  3. Test-FetchMap    (HEAD-check all URLs)`n  4. Invoke-Fetch     (download installers)`n  5. New-RepoChecksums (SHA256 hashes)`n  6. Fill-PackagesTypes (detect MSI/NSIS/Inno/etc.)`n`nSet REPO_HOST env var or create Config\\RepoHost.txt with the server name." }
      @{ Title = 'Go-Live Pipeline: Stage and Preflight'; Highlights = @(); Body = "After fetching, stage to client PCs:`n`n  .\\Config\\Stage-To-Clients.ps1`n`nThis uses robocopy to push the repo to target machines.`n`nBefore deploying, run preflight:`n`n  .\\Config\\Run-Preflight.ps1`n`nThis checks that all expected files are present and hashes match.`n`nUse Runbook-Inventory.ps1 to compare installed software against the expected list.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'DeployShortcuts' = @{
    Label = [char]0x2398 + '  Deploy Shortcuts'
    Desc  = 'Push desktop shortcuts to workstations'
    Color = [System.Drawing.Color]::FromArgb(80,130,60)
    Steps = @(
      @{ Title = 'Deploy Shortcuts: Overview'; Highlights = @(); Body = "EnvSetup\\Deploy-Shortcuts.ps1 copies shortcut files (.lnk) to the Public Desktop on remote workstations.`n`nFeatures:`n  - Authenticates via net.exe (handles 1219/3775 multi-connection errors)`n  - Detects bad passwords (1326) and re-prompts once`n  - Never overwrites existing files (logs EXISTS_DIFFERENT or UPTODATE)`n  - Supports -WhatIf for dry runs`n  - Writes structured CSV + human-readable log + transcript" }
      @{ Title = 'Deploy Shortcuts: Dry Run'; Highlights = @(); Body = "Always start with a dry run:`n`n  .\\EnvSetup\\Deploy-Shortcuts.ps1 -WhatIf`n`nThis shows what would be copied without touching any machines.`n`nTo target specific machines instead of the default range:`n  .\\EnvSetup\\Deploy-Shortcuts.ps1 -ComputerList 'PC001','PC002' -WhatIf`n`nLogs are written to C:\\ShortcutDeployLogs." }
      @{ Title = 'Deploy Shortcuts: Apply'; Highlights = @(); Body = "When the dry run looks correct:`n`n  .\\EnvSetup\\Deploy-Shortcuts.ps1`n`nYou will be prompted for credentials. The script handles SMB auth automatically.`n`nCheck the logs folder for:`n  - DeployShortcuts_*.csv  (per-host, per-file status)`n  - DeployShortcuts_*.txt  (human-readable summary)`n  - Transcript_*.txt       (full console output)`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'QueueInventory' = @{
    Label = [char]0x2399 + '  Queue Inventory'
    Desc  = 'Inventory print queues with SNMP details'
    Color = [System.Drawing.Color]::FromArgb(100,80,160)
    Steps = @(
      @{ Title = 'Queue Inventory: Overview'; Highlights = @(); Body = "GetInfo\\QueueInventory.ps1 takes printer queue names from a print server, resolves them to IP addresses, and collects SNMP info (MAC, serial, model).`n`nUseful for:`n  - Building a printer asset database`n  - Cross-referencing queue names with physical devices`n  - Feeding into the Printer Mapping workflow" }
      @{ Title = 'Queue Inventory: Run It'; Highlights = @(); Body = "Open a PowerShell terminal and run:`n`n  .\\GetInfo\\QueueInventory.ps1 -PrintServer YOURSERVER -Queues 'Queue1','Queue2'`n`nOr let it use the defaults and edit the script parameters.`n`nThe output CSV lands at the -OutputPath (default: C:\\Temp\\QueueInventory.csv).`n`nColumns: QueueName, IPAddress, MAC, Serial, Model, Status`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'OCRFloorPlan' = @{
    Label = [char]0x2316 + '  OCR Floor Plan'
    Desc  = 'Extract workstation/printer positions from floor plans'
    Color = [System.Drawing.Color]::FromArgb(140,60,120)
    Steps = @(
      @{ Title = 'OCR Floor Plan: Overview'; Highlights = @(); Body = "The OCR folder contains Python tools for extracting workstation and printer positions from annotated floor plan images.`n`n  locus_mapping_ocr.py  -- detect red (workstation) and green (printer) circles, OCR their labels, compute nearest-printer mapping`n  build_host_unc_csv.py -- build a host-to-UNC mapping CSV from OCR output`n  printer_lookup.csv    -- reference data for printer queue names`n`nRequires: Python 3, opencv-python-headless, pillow, pytesseract, numpy, pandas, and Tesseract OCR engine." }
      @{ Title = 'OCR Floor Plan: Run It'; Highlights = @(); Body = "From the OCR folder:`n`n  python locus_mapping_ocr.py --workstations ws.png --printers pr.png --out-prefix ls111`n`nOutputs:`n  ls111-workstations.csv  (WorkstationID, x, y)`n  ls111-printers.csv      (PrinterID, x, y)`n  ls111-nearest.csv       (WorkstationID, PrinterID, DistancePx)`n  ls111-overlay-ws.png    (debug overlay)`n  ls111-overlay-pr.png    (debug overlay)`n`nThen run build_host_unc_csv.py to generate the mapping CSV for the Printer Mapping workflow.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'MonitorIdentification' = @{
    Label = [char]0x2316 + '  Monitor Identification'
    Desc  = 'Identify displays, diagnose dock phantoms, export HTML'
    Color = [System.Drawing.Color]::FromArgb(60,120,180)
    Steps = @(
      @{ Title = 'Monitor ID: Overview'; Highlights = @(); Body = "GetInfo\Get-MonitorInfo.psm1 bridges WMI monitor hardware data (model, serial, manufacturer) with the Windows display topology (Settings display number, primary status, screen coordinates).`n`nFour exported functions:`n  Get-MonitorInfo           -- live inventory`n  Invoke-MonitorDiff        -- before/after cable-swap diff`n  Reset-DisplayDeviceCache  -- flush dock EDID cache`n  Export-MonitorInfoHtml    -- dark-themed HTML report`n`nNo network required -- all data comes from the local machine." }
      @{ Title = 'Monitor ID: Quick Start'; Highlights = @(); Body = "Open a PowerShell terminal and run:`n`n  Import-Module .\GetInfo\Get-MonitorInfo.psm1 -Force`n  Get-MonitorInfo | Format-List`n`nEach object includes:`n  DisplayNumber, IsPrimary, Model, Serial,`n  Manufacturer, Resolution, ScreenBounds,`n  Connection, DevicePath, Adapter`n`nThe DisplayNumber matches what you see in`nSettings > System > Display (the circled numbers)." }
      @{ Title = 'Monitor ID: Cable-Swap Diff'; Highlights = @(); Body = "To compare before and after swapping cables or docks:`n`n  Import-Module .\GetInfo\Get-MonitorInfo.psm1 -Force`n  Invoke-MonitorDiff`n`nThis captures a snapshot, prompts you to make your change, then captures a second snapshot and shows what Appeared, Disappeared, Changed, or stayed Unchanged.`n`nFor scripted pipelines:`n  `$before = Get-MonitorInfo`n  # ... swap cables ...`n  Invoke-MonitorDiff -BeforeSnapshot `$before -NonInteractive" }
      @{ Title = 'Monitor ID: Dock Phantom Displays'; Highlights = @(); Body = "DisplayLink docks (like the ThinkPad Hybrid USB-C) cache EDID from the last-connected monitor in firmware. WMI reports these phantoms as Active/OK/Present even when nothing is plugged in.`n`nTo flush the cache (requires elevation):`n`n  Reset-DisplayDeviceCache`n  Get-MonitorInfo | Format-List`n`nNow only physically-connected monitors appear.`n`nKey insight: UIDs on the dock are port-bound, not monitor-bound. Swapping cables swaps which monitor gets which UID and display number." }
      @{ Title = 'Monitor ID: HTML Report'; Highlights = @(); Body = "Generate a dark-themed HTML report (same style as RPM-Recon):`n`n  Import-Module .\GetInfo\Get-MonitorInfo.psm1 -Force`n  Export-MonitorInfoHtml -Open`n`nWith diff data:`n  `$before = Get-MonitorInfo`n  # ... swap cables ...`n  `$diff = Invoke-MonitorDiff -BeforeSnapshot `$before -NonInteractive`n  Export-MonitorInfoHtml -DiffResults `$diff -Open`n`nThe report includes summary chips, a monitor table with PRIMARY/DISCONNECTED badges, phantom row highlighting, and a Dock Insights panel.`n`nPress the Menu button below to try another tutorial." }
    )
  }
  'UtilitiesOverview' = @{
    Label = [char]0x2630 + '  Utilities Overview'
    Desc  = 'Screenshot, file share, unblock, and more'
    Color = [System.Drawing.Color]::FromArgb(90,90,140)
    Steps = @(
      @{ Title = 'Utilities: What Is Available'; Highlights = @(); Body = "The Utilities folder contains standalone helpers:`n`n  Take-Screenshot.ps1    -- capture the primary screen to PNG`n  Unblock-All.ps1        -- remove Zone.Identifier locks from downloaded files`n  Invoke-FileShare.ps1   -- open/map/test file shares`n  Test-Network.ps1       -- ICMP, DNS, TCP port checks`n  Map-Printer.ps1        -- quick single-printer map/remove`n  Invoke-RunControl.ps1  -- run control hooks for the GUI`n  Invoke-UndoRedo.ps1    -- undo/redo support for mapping" }
      @{ Title = 'Utilities: Take-Screenshot'; Highlights = @(); Body = "Capture the primary monitor to a PNG file:`n`n  . .\\Utilities\\Take-Screenshot.ps1`n  Take-Screenshot -Path C:\\Temp\\screen.png`n`nUseful for documenting before/after states during deployments." }
      @{ Title = 'Utilities: Unblock-All'; Highlights = @(); Body = "When you download scripts from the internet, Windows adds a Zone.Identifier stream that blocks execution.`n`n  .\\Utilities\\Unblock-All.ps1`n`nThis removes the lock from all files in the repo. The tools\\Invoke-RepoFileHealth.ps1 also does this as part of its full scan.`n`nPress the Menu button below to try another tutorial." }
    )
  }
}

# The active tutorial steps array -- starts as the menu (set by Show-TutorialMenu)
$script:TutorialSteps = @()
$script:TutorialIndex = 0
$script:TutorialActive = $false
$script:TutorialShownOnce = $false
$script:TutorialCheckpoints = @{}
$script:HighlightedControls = @()
$script:TutorialInMenu = $true  # true = showing the menu, false = in a track
$script:GlowOn = $true
$script:GlowColorA = [System.Drawing.Color]::FromArgb(255,215,0)   # Gold
$script:GlowColorB = [System.Drawing.Color]::FromArgb(255,255,120) # Bright yellow

function Clear-TutorialHighlight {
  foreach ($entry in $script:HighlightedControls) {
    $ctrl = $entry.Control
    if ($null -ne $entry.BackColor) { $ctrl.BackColor = $entry.BackColor }
    if ($null -ne $entry.ForeColor) { $ctrl.ForeColor = $entry.ForeColor }
  }
  $script:HighlightedControls = @()
}

# Highlight controls -- preserves green/red identity on Start/Stop buttons by pulsing ForeColor instead
function Apply-TutorialHighlights {
  param([string[]]$Names)
  Clear-TutorialHighlight
  if (-not $Names -or $Names.Count -eq 0) { return }
  $list = [System.Collections.Generic.List[psobject]]::new()
  $identityButtons = @('btnStartWorker','btnStartController','btnStop')
  foreach ($name in $Names) {
    if (-not $name) { continue }
    $ctrl = Get-Variable -Name $name -ValueOnly -ErrorAction SilentlyContinue
    if (-not $ctrl) { continue }
    $entry = [pscustomobject]@{ Control = $ctrl; BackColor = $ctrl.BackColor; ForeColor = $ctrl.ForeColor; IsIdentity = ($identityButtons -contains $name) }
    $list.Add($entry)
    if ($identityButtons -contains $name) {
      # Don't change BackColor on green GO / red STOP -- pulse ForeColor instead
      $ctrl.ForeColor = $script:GlowColorA
    } else {
      $ctrl.BackColor = $script:GlowColorA
      if ($ctrl -is [System.Windows.Forms.GroupBox] -or $ctrl -is [System.Windows.Forms.Label]) {
        $ctrl.ForeColor = [System.Drawing.Color]::FromArgb(140,80,0)
      } elseif ($ctrl -is [System.Windows.Forms.Button]) {
        $ctrl.ForeColor = [System.Drawing.Color]::Black
      }
    }
  }
  $script:HighlightedControls = $list.ToArray()
  $script:GlowOn = $true
}

# Timer that pulses highlighted controls
$script:GlowTimer = New-Object System.Windows.Forms.Timer
$script:GlowTimer.Interval = 600
$script:GlowTimer.Add_Tick({
  try {
    if ($script:HighlightedControls.Count -eq 0) { return }
    $script:GlowOn = -not $script:GlowOn
    $colorA = $script:GlowColorA; $colorB = $script:GlowColorB
    $color = if ($script:GlowOn) { $colorA } else { $colorB }
    foreach ($entry in $script:HighlightedControls) {
      if ($entry.IsIdentity) {
        $entry.Control.ForeColor = $color  # pulse text color, keep green/red background
      } else {
        $entry.Control.BackColor = $color
      }
    }
  } catch [System.Management.Automation.PipelineStoppedException] { <# Ctrl+C in host — ignore #> }
})
$script:GlowTimer.Start()

# Show the tutorial menu (track picker) inside the tutorial panel
function Show-TutorialMenu {
  $script:TutorialInMenu = $true
  $script:TutorialSteps = @()
  $script:TutorialIndex = 0
  Clear-TutorialHighlight
  # Hide step navigation, show menu buttons
  $script:TutorialTitleLabel.Text = 'Choose a Tutorial'
  $script:TutorialBodyLabel.Text = "Pick a use case below to get a short, guided walkthrough.`nEach tutorial is 3-5 steps and shows you real output at the end."
  $script:TutorialBodyLabel.Font = New-Object System.Drawing.Font('Segoe UI',9.5)
  $script:TutorialCounter.Text = ''
  $script:TutorialBtnPrev.Visible = $false
  $script:TutorialBtnNext.Visible = $false
  $script:TutorialBtnMenu.Visible = $false
  # Show track buttons
  foreach ($btn in $script:TrackButtons) { $btn.Visible = $true }
}

function Start-TutorialTrack {
  param([string]$TrackKey)
  $track = $script:TutorialTracks[$TrackKey]
  if (-not $track) { return }
  $script:TutorialSteps = $track.Steps
  $script:TutorialIndex = 0
  $script:TutorialInMenu = $false
  # Hide track buttons, show step navigation
  foreach ($btn in $script:TrackButtons) { $btn.Visible = $false }
  $script:TutorialBtnPrev.Visible = $true
  $script:TutorialBtnNext.Visible = $true
  $script:TutorialBtnMenu.Visible = $true
  Update-TutorialView
}

function Show-Tutorial {
  param([int]$StepIndex = -1)
  $script:TutorialActive = $true
  if ($script:TutorialInMenu -or $script:TutorialSteps.Count -eq 0) {
    Show-TutorialMenu
  } elseif ($StepIndex -ge 0 -and $StepIndex -lt $script:TutorialSteps.Count) {
    $script:TutorialIndex = $StepIndex
    Update-TutorialView
  }
  $script:TutorialPanel.Visible = $true
  $script:TutorialPanel.BringToFront()
}

function Hide-Tutorial {
  $script:TutorialActive = $false
  $script:TutorialPanel.Visible = $false
  Clear-TutorialHighlight
}

function Update-TutorialView {
  if ($script:TutorialInMenu) { return }
  $step = $script:TutorialSteps[$script:TutorialIndex]
  $script:TutorialTitleLabel.Text = $step.Title
  $script:TutorialBodyLabel.Text = $step.Body
  $script:TutorialCounter.Text = "Step $($script:TutorialIndex + 1) of $($script:TutorialSteps.Count)"
  $script:TutorialBtnPrev.Enabled = $script:TutorialIndex -gt 0
  $script:TutorialBtnNext.Enabled = $script:TutorialIndex -lt ($script:TutorialSteps.Count - 1)
  if ($step.Title -match '^Example:') {
    $script:TutorialBodyLabel.Font = New-Object System.Drawing.Font('Consolas',8.5)
  } else {
    $script:TutorialBodyLabel.Font = New-Object System.Drawing.Font('Segoe UI',9.5)
  }
  Apply-TutorialHighlights -Names $step.Highlights
}

function Show-TutorialAtCheckpoint {
  param([string]$CheckpointName, [int]$StepIndex = 0)
  if ($script:TutorialCheckpoints[$CheckpointName]) { return }
  $script:TutorialCheckpoints[$CheckpointName] = $true
  Show-Tutorial -StepIndex $StepIndex
}

$script:LoadedSession = $null
$script:LastRunSession = $null
$script:StatusCategoryLabel = $null
$script:StatusMessageLabel = $null
$uiFont = New-Object System.Drawing.Font('Segoe UI',9)
$emphasisFont = New-Object System.Drawing.Font('Segoe UI Semibold',9)
$monoFont = New-Object System.Drawing.Font('Consolas',9)
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SysAdminSuite Control Center'
$form.Size = New-Object System.Drawing.Size(1000,820)
$form.MinimumSize = New-Object System.Drawing.Size(1000,820)
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = 'Font'
$form.Font = $uiFont
$form.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)
$form.KeyPreview = $true

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$runTab = New-Object System.Windows.Forms.TabPage
$runTab.Text = 'Run Control'
$kronosTab = New-Object System.Windows.Forms.TabPage
$kronosTab.Text = 'Kronos Lookup'
$runTab.BackColor = [System.Drawing.Color]::WhiteSmoke
$kronosTab.BackColor = [System.Drawing.Color]::WhiteSmoke

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 12000
$toolTip.InitialDelay = 250
$toolTip.ReshowDelay = 150
$toolTip.ShowAlways = $true

# -- Run Tab: GroupBox -- File Paths --
$grpPaths = New-Object System.Windows.Forms.GroupBox
$grpPaths.Text = 'Session File Paths'; $grpPaths.Location = '6,6'; $grpPaths.Size = '952,115'; $grpPaths.Anchor = 'Top, Left, Right'; $grpPaths.Font = $emphasisFont

$lblStop = New-Object System.Windows.Forms.Label
$lblStop.Location = '10,22'; $lblStop.Size = '100,20'; $lblStop.Text = 'Stop signal path'; $lblStop.Font = $emphasisFont
$txtStop = New-Object System.Windows.Forms.TextBox
$txtStop.Location = '115,19'; $txtStop.Size = '575,24'; $txtStop.Text = (Join-Path $repoRoot 'Mapping\Output\Stop.json'); $txtStop.Anchor = 'Top, Left, Right'; $txtStop.Font = $uiFont; $txtStop.ReadOnly = $true; $txtStop.Cursor = 'Hand'; $txtStop.BackColor = [System.Drawing.Color]::White
$btnBrowseStop = New-Object System.Windows.Forms.Button
$btnBrowseStop.Location = '696,18'; $btnBrowseStop.Size = '30,26'; $btnBrowseStop.Text = [char]0x2026; $btnBrowseStop.Anchor = 'Top, Right'; $btnBrowseStop.FlatStyle = 'Flat'; $btnBrowseStop.Font = $uiFont
$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Location = '732,14'; $btnStop.Size = '210,34'; $btnStop.Anchor = 'Top, Right'
$btnStop.Text = [char]0x25A0 + '  STOP Run  (Ctrl+S)'
$btnStop.Font = New-Object System.Drawing.Font('Segoe UI Bold',10); $btnStop.Cursor = 'Hand'
$btnStop.BackColor = [System.Drawing.Color]::FromArgb(200,30,30)
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnStop.FlatStyle = 'Popup'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = '10,52'; $lblStatus.Size = '100,20'; $lblStatus.Text = 'Status path'; $lblStatus.Font = $emphasisFont
$txtStatus = New-Object System.Windows.Forms.TextBox
$txtStatus.Location = '115,49'; $txtStatus.Size = '650,24'; $txtStatus.Text = (Join-Path $repoRoot 'Mapping\Output\status.json'); $txtStatus.Anchor = 'Top, Left, Right'; $txtStatus.Font = $uiFont; $txtStatus.ReadOnly = $true; $txtStatus.Cursor = 'Hand'; $txtStatus.BackColor = [System.Drawing.Color]::White
$btnBrowseStatus = New-Object System.Windows.Forms.Button
$btnBrowseStatus.Location = '772,48'; $btnBrowseStatus.Size = '30,26'; $btnBrowseStatus.Text = [char]0x2026; $btnBrowseStatus.Anchor = 'Top, Right'; $btnBrowseStatus.FlatStyle = 'Flat'; $btnBrowseStatus.Font = $uiFont
$btnStatus = New-Object System.Windows.Forms.Button
$btnStatus.Location = '810,48'; $btnStatus.Size = '130,26'; $btnStatus.Text = 'Refresh Now  (F5)'; $btnStatus.Anchor = 'Top, Right'; $btnStatus.FlatStyle = 'Flat'; $btnStatus.BackColor = [System.Drawing.Color]::White; $btnStatus.Font = $uiFont

$lblUndo = New-Object System.Windows.Forms.Label
$lblUndo.Location = '10,82'; $lblUndo.Size = '100,20'; $lblUndo.Text = 'History path'; $lblUndo.Font = $emphasisFont
$txtUndo = New-Object System.Windows.Forms.TextBox
$txtUndo.Location = '115,79'; $txtUndo.Size = '650,24'; $txtUndo.Text = (Join-Path $repoRoot 'Mapping\Output\UndoRedo.Controller.json'); $txtUndo.Anchor = 'Top, Left, Right'; $txtUndo.Font = $uiFont; $txtUndo.ReadOnly = $true; $txtUndo.Cursor = 'Hand'; $txtUndo.BackColor = [System.Drawing.Color]::White
$btnBrowseHistory = New-Object System.Windows.Forms.Button
$btnBrowseHistory.Location = '772,78'; $btnBrowseHistory.Size = '30,26'; $btnBrowseHistory.Text = [char]0x2026; $btnBrowseHistory.Anchor = 'Top, Right'; $btnBrowseHistory.FlatStyle = 'Flat'; $btnBrowseHistory.Font = $uiFont
$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Location = '810,78'; $btnLoad.Size = '130,26'; $btnLoad.Text = 'Load History  (Ctrl+L)'; $btnLoad.Anchor = 'Top, Right'; $btnLoad.FlatStyle = 'Flat'; $btnLoad.BackColor = [System.Drawing.Color]::White; $btnLoad.Font = $uiFont

$grpPaths.Controls.AddRange(@($lblStop,$txtStop,$btnBrowseStop,$btnStop,$lblStatus,$txtStatus,$btnBrowseStatus,$btnStatus,$lblUndo,$txtUndo,$btnBrowseHistory,$btnLoad))

# -- Run Tab: GroupBox -- Run Options --
$grpOptions = New-Object System.Windows.Forms.GroupBox
$grpOptions.Text = 'Run Options'; $grpOptions.Location = '6,126'; $grpOptions.Size = '952,42'; $grpOptions.Anchor = 'Top, Left, Right'; $grpOptions.Font = $emphasisFont

$chkWhatIf = New-Object System.Windows.Forms.CheckBox
$chkWhatIf.Location = '10,16'; $chkWhatIf.Size = '160,22'; $chkWhatIf.Text = 'WhatIf replay (safe)'; $chkWhatIf.Checked = $true; $chkWhatIf.Font = $uiFont
$chkAutoRefresh = New-Object System.Windows.Forms.CheckBox
$chkAutoRefresh.Location = '180,16'; $chkAutoRefresh.Size = '105,22'; $chkAutoRefresh.Text = 'Auto refresh'; $chkAutoRefresh.Checked = $true; $chkAutoRefresh.Font = $uiFont
$lblRefreshEvery = New-Object System.Windows.Forms.Label
$lblRefreshEvery.Location = '295,18'; $lblRefreshEvery.Size = '70,20'; $lblRefreshEvery.Text = 'Every (sec)'; $lblRefreshEvery.Font = $uiFont
$nudRefreshSeconds = New-Object System.Windows.Forms.NumericUpDown
$nudRefreshSeconds.Location = '370,15'; $nudRefreshSeconds.Size = '55,22'; $nudRefreshSeconds.Minimum = 2; $nudRefreshSeconds.Maximum = 30; $nudRefreshSeconds.Value = 3; $nudRefreshSeconds.Font = $uiFont
$btnUndo = New-Object System.Windows.Forms.Button
$btnUndo.Location = '680,13'; $btnUndo.Size = '130,26'; $btnUndo.Text = 'Undo Top  (Ctrl+Z)'; $btnUndo.FlatStyle = 'Flat'; $btnUndo.BackColor = [System.Drawing.Color]::White; $btnUndo.Anchor = 'Top, Right'; $btnUndo.Font = $uiFont
$btnRedo = New-Object System.Windows.Forms.Button
$btnRedo.Location = '815,13'; $btnRedo.Size = '130,26'; $btnRedo.Text = 'Redo Top  (Ctrl+Y)'; $btnRedo.FlatStyle = 'Flat'; $btnRedo.BackColor = [System.Drawing.Color]::White; $btnRedo.Anchor = 'Top, Right'; $btnRedo.Font = $uiFont

$grpOptions.Controls.AddRange(@($chkWhatIf,$chkAutoRefresh,$lblRefreshEvery,$nudRefreshSeconds,$btnUndo,$btnRedo))

# -- Run Tab: GroupBox -- Launch Configuration --
$grpLaunch = New-Object System.Windows.Forms.GroupBox
$grpLaunch.Text = 'Launch Configuration'; $grpLaunch.Location = '6,172'; $grpLaunch.Size = '952,232'; $grpLaunch.Anchor = 'Top, Left, Right'; $grpLaunch.Font = $emphasisFont

$lblRunTargets = New-Object System.Windows.Forms.Label
$lblRunTargets.Location = '10,20'; $lblRunTargets.Size = '260,18'; $lblRunTargets.Text = 'Controller targets (one per line)'; $lblRunTargets.Font = $emphasisFont
$txtRunTargets = New-Object System.Windows.Forms.TextBox
$txtRunTargets.Location = '10,40'; $txtRunTargets.Size = '280,100'; $txtRunTargets.Multiline = $true; $txtRunTargets.ScrollBars = 'Vertical'; $txtRunTargets.AcceptsReturn = $true; $txtRunTargets.Font = $uiFont
# -- Worker Options: Structured Controls -- Worker options passthrough to controller
$lblRunMode = New-Object System.Windows.Forms.Label
$lblRunMode.Location = '310,20'; $lblRunMode.Size = '65,18'; $lblRunMode.Text = 'Run Mode'; $lblRunMode.Font = $emphasisFont
$cmbRunMode = New-Object System.Windows.Forms.ComboBox
$cmbRunMode.Location = '378,17'; $cmbRunMode.Size = '185,24'; $cmbRunMode.DropDownStyle = 'DropDownList'; $cmbRunMode.Font = $uiFont
@('Recon Only (-ListOnly)','Plan Only (-PlanOnly)','Full Run','Full Run + Prune') | ForEach-Object { [void]$cmbRunMode.Items.Add($_) }
$cmbRunMode.SelectedIndex = 0

$chkPreflight = New-Object System.Windows.Forms.CheckBox
$chkPreflight.Location = '575,19'; $chkPreflight.Size = '80,20'; $chkPreflight.Text = 'Preflight'; $chkPreflight.Checked = $true; $chkPreflight.Font = $uiFont
$chkRestartSpooler = New-Object System.Windows.Forms.CheckBox
$chkRestartSpooler.Location = '660,19'; $chkRestartSpooler.Size = '130,20'; $chkRestartSpooler.Text = 'Restart Spooler'; $chkRestartSpooler.Font = $uiFont

$lblQueuesAdd = New-Object System.Windows.Forms.Label
$lblQueuesAdd.Location = '310,42'; $lblQueuesAdd.Size = '90,16'; $lblQueuesAdd.Text = 'Queues to Add'; $lblQueuesAdd.Font = $uiFont
$txtQueuesAdd = New-Object System.Windows.Forms.TextBox
$txtQueuesAdd.Location = '310,58'; $txtQueuesAdd.Size = '215,50'; $txtQueuesAdd.Multiline = $true; $txtQueuesAdd.ScrollBars = 'Vertical'; $txtQueuesAdd.AcceptsReturn = $true; $txtQueuesAdd.Font = $uiFont

$lblQueuesRemove = New-Object System.Windows.Forms.Label
$lblQueuesRemove.Location = '535,42'; $lblQueuesRemove.Size = '108,16'; $lblQueuesRemove.Text = 'Queues to Remove'; $lblQueuesRemove.Font = $uiFont
$txtQueuesRemove = New-Object System.Windows.Forms.TextBox
$txtQueuesRemove.Location = '535,58'; $txtQueuesRemove.Size = '195,50'; $txtQueuesRemove.Multiline = $true; $txtQueuesRemove.ScrollBars = 'Vertical'; $txtQueuesRemove.AcceptsReturn = $true; $txtQueuesRemove.Font = $uiFont

$lblDefaultQueue = New-Object System.Windows.Forms.Label
$lblDefaultQueue.Location = '740,42'; $lblDefaultQueue.Size = '90,16'; $lblDefaultQueue.Text = 'Default Queue'; $lblDefaultQueue.Font = $uiFont
$txtDefaultQueue = New-Object System.Windows.Forms.TextBox
$txtDefaultQueue.Location = '740,58'; $txtDefaultQueue.Size = '200,24'; $txtDefaultQueue.Font = $uiFont; $txtDefaultQueue.Anchor = 'Top, Left, Right'

$lblGeneratedOpts = New-Object System.Windows.Forms.Label
$lblGeneratedOpts.Location = '310,112'; $lblGeneratedOpts.Size = '120,16'; $lblGeneratedOpts.Text = 'Generated Options'; $lblGeneratedOpts.Font = $uiFont
$txtWorkerOptions = New-Object System.Windows.Forms.TextBox
$txtWorkerOptions.Location = '310,128'; $txtWorkerOptions.Size = '630,22'; $txtWorkerOptions.ReadOnly = $true; $txtWorkerOptions.Font = $monoFont; $txtWorkerOptions.BackColor = [System.Drawing.Color]::FromArgb(240,240,240); $txtWorkerOptions.Anchor = 'Top, Left, Right'; $txtWorkerOptions.Text = '-ListOnly -Preflight'

# Auto-rebuild options when any structured control changes
$rebuildHandler = { Build-WorkerOptionsString }
$cmbRunMode.Add_SelectedIndexChanged($rebuildHandler)
$chkPreflight.Add_CheckedChanged($rebuildHandler)
$chkRestartSpooler.Add_CheckedChanged($rebuildHandler)
$txtQueuesAdd.Add_TextChanged($rebuildHandler)
$txtQueuesRemove.Add_TextChanged($rebuildHandler)
$txtDefaultQueue.Add_TextChanged($rebuildHandler)

$btnExampleOptions = New-Object System.Windows.Forms.Button
$btnExampleOptions.Location = '10,146'; $btnExampleOptions.Size = '135,26'; $btnExampleOptions.Text = 'Load Safe Example'; $btnExampleOptions.FlatStyle = 'Flat'; $btnExampleOptions.BackColor = [System.Drawing.Color]::White; $btnExampleOptions.Font = $uiFont
$btnOpenSession = New-Object System.Windows.Forms.Button
$btnOpenSession.Location = '152,146'; $btnOpenSession.Size = '140,26'; $btnOpenSession.Text = 'Open Session Folder'; $btnOpenSession.FlatStyle = 'Flat'; $btnOpenSession.BackColor = [System.Drawing.Color]::White; $btnOpenSession.Font = $uiFont
$btnCopyStatus = New-Object System.Windows.Forms.Button
$btnCopyStatus.Location = '300,146'; $btnCopyStatus.Size = '110,26'; $btnCopyStatus.Text = 'Copy Status'; $btnCopyStatus.FlatStyle = 'Flat'; $btnCopyStatus.BackColor = [System.Drawing.Color]::White; $btnCopyStatus.Font = $uiFont
$btnCopyHistory = New-Object System.Windows.Forms.Button
$btnCopyHistory.Location = '418,146'; $btnCopyHistory.Size = '110,26'; $btnCopyHistory.Text = 'Copy History'; $btnCopyHistory.FlatStyle = 'Flat'; $btnCopyHistory.BackColor = [System.Drawing.Color]::White; $btnCopyHistory.Font = $uiFont

# -- Big green GO and red STOP buttons --
$bigBtnFont = New-Object System.Drawing.Font('Segoe UI Bold',11)
$btnStartWorker = New-Object System.Windows.Forms.Button
$btnStartWorker.Location = '10,180'; $btnStartWorker.Size = '310,42'; $btnStartWorker.Anchor = 'Top, Left, Right'
$btnStartWorker.Text = [char]0x25B6 + '  START Local Worker  (this PC only)'
$btnStartWorker.Font = $bigBtnFont; $btnStartWorker.Cursor = 'Hand'
$btnStartWorker.BackColor = [System.Drawing.Color]::FromArgb(30,150,30)
$btnStartWorker.ForeColor = [System.Drawing.Color]::White
$btnStartWorker.FlatStyle = 'Popup'

$btnStartController = New-Object System.Windows.Forms.Button
$btnStartController.Location = '328,180'; $btnStartController.Size = '310,42'; $btnStartController.Anchor = 'Top, Left, Right'
$btnStartController.Text = [char]0x25B6 + '  START Controller  (push to targets)'
$btnStartController.Font = $bigBtnFont; $btnStartController.Cursor = 'Hand'
$btnStartController.BackColor = [System.Drawing.Color]::FromArgb(30,150,30)
$btnStartController.ForeColor = [System.Drawing.Color]::White
$btnStartController.FlatStyle = 'Popup'

$grpLaunch.Controls.AddRange(@($lblRunTargets,$txtRunTargets,$lblRunMode,$cmbRunMode,$chkPreflight,$chkRestartSpooler,$lblQueuesAdd,$txtQueuesAdd,$lblQueuesRemove,$txtQueuesRemove,$lblDefaultQueue,$txtDefaultQueue,$lblGeneratedOpts,$txtWorkerOptions,$btnExampleOptions,$btnOpenSession,$btnCopyStatus,$btnCopyHistory,$btnStartWorker,$btnStartController))

# -- Run Tab: Status & History panes --
$lblStatusPane = New-Object System.Windows.Forms.Label
$lblStatusPane.Location = '8,409'; $lblStatusPane.Size = '120,18'; $lblStatusPane.Text = 'Run Status'; $lblStatusPane.Font = $emphasisFont
$txtStatusView = New-Object System.Windows.Forms.TextBox
$txtStatusView.Location = '6,428'; $txtStatusView.Size = '952,95'; $txtStatusView.Multiline = $true; $txtStatusView.ScrollBars = 'Both'; $txtStatusView.ReadOnly = $true; $txtStatusView.Anchor = 'Top, Left, Right'; $txtStatusView.Font = $monoFont; $txtStatusView.WordWrap = $false; $txtStatusView.BackColor = [System.Drawing.Color]::White; $txtStatusView.Text = 'Launch a run or click Refresh Now to inspect a status snapshot.'
$lblHistoryPane = New-Object System.Windows.Forms.Label
$lblHistoryPane.Location = '8,527'; $lblHistoryPane.Size = '120,18'; $lblHistoryPane.Text = 'Undo / Redo History'; $lblHistoryPane.Font = $emphasisFont
$txtHistoryView = New-Object System.Windows.Forms.TextBox
$txtHistoryView.Location = '6,547'; $txtHistoryView.Size = '952,178'; $txtHistoryView.Multiline = $true; $txtHistoryView.ScrollBars = 'Both'; $txtHistoryView.ReadOnly = $true; $txtHistoryView.Anchor = 'Top, Bottom, Left, Right'; $txtHistoryView.Font = $monoFont; $txtHistoryView.WordWrap = $false; $txtHistoryView.BackColor = [System.Drawing.Color]::White; $txtHistoryView.Text = 'Launch a run or load a history file to inspect undo/redo details.'

$runTab.Controls.AddRange(@($grpPaths,$grpOptions,$grpLaunch,$lblStatusPane,$txtStatusView,$lblHistoryPane,$txtHistoryView))

# -- Kronos Tab: GroupBox -- Probe & Inventory --
$grpKronos = New-Object System.Windows.Forms.GroupBox
$grpKronos.Text = 'Kronos Clock Probe / Inventory'; $grpKronos.Location = '6,6'; $grpKronos.Size = '952,220'; $grpKronos.Anchor = 'Top, Left, Right'; $grpKronos.Font = $emphasisFont

$lblTargets = New-Object System.Windows.Forms.Label
$lblTargets.Location = '10,22'; $lblTargets.Size = '180,18'; $lblTargets.Text = 'Targets (one per line)'; $lblTargets.Font = $emphasisFont
$txtTargets = New-Object System.Windows.Forms.TextBox
$txtTargets.Location = '10,42'; $txtTargets.Size = '280,165'; $txtTargets.Multiline = $true; $txtTargets.ScrollBars = 'Vertical'; $txtTargets.AcceptsReturn = $true; $txtTargets.Font = $uiFont

$lblClockOut = New-Object System.Windows.Forms.Label
$lblClockOut.Location = '310,22'; $lblClockOut.Size = '90,18'; $lblClockOut.Text = 'Output CSV'; $lblClockOut.Font = $emphasisFont
$txtClockOut = New-Object System.Windows.Forms.TextBox
$txtClockOut.Location = '310,42'; $txtClockOut.Size = '590,24'; $txtClockOut.Text = (Join-Path $repoRoot 'GetInfo\KronosClockInventory.csv'); $txtClockOut.Anchor = 'Top, Left, Right'; $txtClockOut.Font = $uiFont; $txtClockOut.ReadOnly = $true; $txtClockOut.Cursor = 'Hand'; $txtClockOut.BackColor = [System.Drawing.Color]::White
$btnBrowseClockOut = New-Object System.Windows.Forms.Button
$btnBrowseClockOut.Location = '906,41'; $btnBrowseClockOut.Size = '30,26'; $btnBrowseClockOut.Text = [char]0x2026; $btnBrowseClockOut.Anchor = 'Top, Right'; $btnBrowseClockOut.FlatStyle = 'Flat'; $btnBrowseClockOut.Font = $uiFont

$lblInv = New-Object System.Windows.Forms.Label
$lblInv.Location = '310,74'; $lblInv.Size = '100,18'; $lblInv.Text = 'Inventory CSV'; $lblInv.Font = $emphasisFont
$txtInv = New-Object System.Windows.Forms.TextBox
$txtInv.Location = '310,94'; $txtInv.Size = '590,24'; $txtInv.Text = $txtClockOut.Text; $txtInv.Anchor = 'Top, Left, Right'; $txtInv.Font = $uiFont; $txtInv.ReadOnly = $true; $txtInv.Cursor = 'Hand'; $txtInv.BackColor = [System.Drawing.Color]::White
$btnBrowseInv = New-Object System.Windows.Forms.Button
$btnBrowseInv.Location = '906,93'; $btnBrowseInv.Size = '30,26'; $btnBrowseInv.Text = [char]0x2026; $btnBrowseInv.Anchor = 'Top, Right'; $btnBrowseInv.FlatStyle = 'Flat'; $btnBrowseInv.Font = $uiFont

$cmbLookup = New-Object System.Windows.Forms.ComboBox
$cmbLookup.Location = '310,128'; $cmbLookup.Size = '150,24'; $cmbLookup.DropDownStyle = 'DropDownList'; $cmbLookup.Font = $uiFont
@('Any','IP','MAC','Serial','HostName','DeviceName') | ForEach-Object { [void]$cmbLookup.Items.Add($_) }
$cmbLookup.SelectedIndex = 0
$txtLookup = New-Object System.Windows.Forms.TextBox
$txtLookup.Location = '470,128'; $txtLookup.Size = '310,24'; $txtLookup.Anchor = 'Top, Left, Right'; $txtLookup.Font = $uiFont
$btnProbe = New-Object System.Windows.Forms.Button
$btnProbe.Location = '795,127'; $btnProbe.Size = '140,26'; $btnProbe.Text = 'Probe Targets'; $btnProbe.Anchor = 'Top, Right'; $btnProbe.FlatStyle = 'Flat'; $btnProbe.BackColor = [System.Drawing.Color]::FromArgb(225,240,255); $btnProbe.Font = $emphasisFont

$btnInventory = New-Object System.Windows.Forms.Button
$btnInventory.Location = '310,162'; $btnInventory.Size = '150,26'; $btnInventory.Text = 'Load Inventory'; $btnInventory.FlatStyle = 'Flat'; $btnInventory.BackColor = [System.Drawing.Color]::White; $btnInventory.Font = $uiFont
$btnFind = New-Object System.Windows.Forms.Button
$btnFind.Location = '470,162'; $btnFind.Size = '140,26'; $btnFind.Text = 'Find Match'; $btnFind.FlatStyle = 'Flat'; $btnFind.BackColor = [System.Drawing.Color]::White; $btnFind.Font = $uiFont
$btnCopyClockResults = New-Object System.Windows.Forms.Button
$btnCopyClockResults.Location = '795,162'; $btnCopyClockResults.Size = '140,26'; $btnCopyClockResults.Text = 'Copy Results'; $btnCopyClockResults.Anchor = 'Top, Right'; $btnCopyClockResults.FlatStyle = 'Flat'; $btnCopyClockResults.BackColor = [System.Drawing.Color]::White; $btnCopyClockResults.Font = $uiFont

$grpKronos.Controls.AddRange(@($lblTargets,$txtTargets,$lblClockOut,$txtClockOut,$btnBrowseClockOut,$lblInv,$txtInv,$btnBrowseInv,$cmbLookup,$txtLookup,$btnProbe,$btnInventory,$btnFind,$btnCopyClockResults))

# -- Kronos Tab: Results pane --
$lblKronosResults = New-Object System.Windows.Forms.Label
$lblKronosResults.Location = '8,230'; $lblKronosResults.Size = '140,18'; $lblKronosResults.Text = 'Results'; $lblKronosResults.Font = $emphasisFont
$txtClockResults = New-Object System.Windows.Forms.TextBox
$txtClockResults.Location = '6,250'; $txtClockResults.Size = '952,400'; $txtClockResults.Multiline = $true; $txtClockResults.ScrollBars = 'Both'; $txtClockResults.ReadOnly = $true; $txtClockResults.Anchor = 'Top, Bottom, Left, Right'; $txtClockResults.Font = $monoFont; $txtClockResults.WordWrap = $false; $txtClockResults.BackColor = [System.Drawing.Color]::White; $txtClockResults.Text = 'Probe live clocks or search a saved inventory CSV.'

$kronosTab.Controls.AddRange(@($grpKronos,$lblKronosResults,$txtClockResults))

# -- Machine Info Tab --
$machineInfoTab = New-Object System.Windows.Forms.TabPage
$machineInfoTab.Text = 'Machine Info'
$machineInfoTab.BackColor = [System.Drawing.Color]::WhiteSmoke

$machineInfoScript = Join-Path $repoRoot 'GetInfo\Get-MachineInfo.ps1'
$printerMacScript  = Join-Path $repoRoot 'GetInfo\Get-PrinterMacSerial.ps1'

# -- Machine Info: GroupBox -- Script Picker & Inputs --
$grpMI = New-Object System.Windows.Forms.GroupBox
$grpMI.Text = 'Machine / Printer Info Probe'; $grpMI.Location = '6,6'; $grpMI.Size = '952,210'; $grpMI.Anchor = 'Top, Left, Right'; $grpMI.Font = $emphasisFont

$lblMIMode = New-Object System.Windows.Forms.Label
$lblMIMode.Location = '10,22'; $lblMIMode.Size = '70,18'; $lblMIMode.Text = 'Script'; $lblMIMode.Font = $emphasisFont
$cmbMIMode = New-Object System.Windows.Forms.ComboBox
$cmbMIMode.Location = '80,19'; $cmbMIMode.Size = '280,24'; $cmbMIMode.DropDownStyle = 'DropDownList'; $cmbMIMode.Font = $uiFont
@('Get-MachineInfo  (workstation serial/IP/MAC)','Get-PrinterMacSerial  (printer MAC/serial via SNMP)') | ForEach-Object { [void]$cmbMIMode.Items.Add($_) }
$cmbMIMode.SelectedIndex = 0

$lblMITargets = New-Object System.Windows.Forms.Label
$lblMITargets.Location = '10,50'; $lblMITargets.Size = '280,18'; $lblMITargets.Text = 'Targets (one hostname or IP per line)'; $lblMITargets.Font = $emphasisFont
$txtMITargets = New-Object System.Windows.Forms.TextBox
$txtMITargets.Location = '10,70'; $txtMITargets.Size = '350,128'; $txtMITargets.Multiline = $true; $txtMITargets.ScrollBars = 'Vertical'; $txtMITargets.AcceptsReturn = $true; $txtMITargets.Font = $uiFont

$lblMIOutCsv = New-Object System.Windows.Forms.Label
$lblMIOutCsv.Location = '380,22'; $lblMIOutCsv.Size = '80,18'; $lblMIOutCsv.Text = 'Output CSV'; $lblMIOutCsv.Font = $emphasisFont
$txtMIOutCsv = New-Object System.Windows.Forms.TextBox
$txtMIOutCsv.Location = '380,42'; $txtMIOutCsv.Size = '500,24'; $txtMIOutCsv.Anchor = 'Top, Left, Right'; $txtMIOutCsv.Font = $uiFont
$txtMIOutCsv.Text = (Join-Path $repoRoot 'GetInfo\MachineInfo_Output.csv')
$btnBrowseMIOut = New-Object System.Windows.Forms.Button
$btnBrowseMIOut.Location = '886,41'; $btnBrowseMIOut.Size = '30,26'; $btnBrowseMIOut.Text = [char]0x2026; $btnBrowseMIOut.Anchor = 'Top, Right'; $btnBrowseMIOut.FlatStyle = 'Flat'; $btnBrowseMIOut.Font = $uiFont
$btnBrowseMIOut.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select output CSV path' -Filter 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'; if ($p) { $txtMIOutCsv.Text = $p } })

$lblMIListPath = New-Object System.Windows.Forms.Label
$lblMIListPath.Location = '380,72'; $lblMIListPath.Size = '160,18'; $lblMIListPath.Text = 'Host List File (optional)'; $lblMIListPath.Font = $emphasisFont
$txtMIListPath = New-Object System.Windows.Forms.TextBox
$txtMIListPath.Location = '380,92'; $txtMIListPath.Size = '500,24'; $txtMIListPath.Anchor = 'Top, Left, Right'; $txtMIListPath.Font = $uiFont; $txtMIListPath.ReadOnly = $true; $txtMIListPath.Cursor = 'Hand'; $txtMIListPath.BackColor = [System.Drawing.Color]::White
$btnBrowseMIList = New-Object System.Windows.Forms.Button
$btnBrowseMIList.Location = '886,91'; $btnBrowseMIList.Size = '30,26'; $btnBrowseMIList.Text = [char]0x2026; $btnBrowseMIList.Anchor = 'Top, Right'; $btnBrowseMIList.FlatStyle = 'Flat'; $btnBrowseMIList.Font = $uiFont
$btnBrowseMIList.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select host list file' -Filter 'Text files (*.txt)|*.txt|CSV files (*.csv)|*.csv|All files (*.*)|*.*'; if ($p) { $txtMIListPath.Text = $p } })
$txtMIListPath.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select host list file' -Filter 'Text files (*.txt)|*.txt|CSV files (*.csv)|*.csv|All files (*.*)|*.*'; if ($p) { $txtMIListPath.Text = $p } })

$lblMIThrottle = New-Object System.Windows.Forms.Label
$lblMIThrottle.Location = '380,122'; $lblMIThrottle.Size = '60,18'; $lblMIThrottle.Text = 'Throttle'; $lblMIThrottle.Font = $uiFont
$nudMIThrottle = New-Object System.Windows.Forms.NumericUpDown
$nudMIThrottle.Location = '445,120'; $nudMIThrottle.Size = '55,22'; $nudMIThrottle.Minimum = 1; $nudMIThrottle.Maximum = 100; $nudMIThrottle.Value = 15; $nudMIThrottle.Font = $uiFont

$btnMIRun = New-Object System.Windows.Forms.Button
$btnMIRun.Location = '380,155'; $btnMIRun.Size = '220,42'; $btnMIRun.Font = New-Object System.Drawing.Font('Segoe UI Bold',11); $btnMIRun.Cursor = 'Hand'
$btnMIRun.Text = [char]0x25B6 + '  Run Probe'
$btnMIRun.BackColor = [System.Drawing.Color]::FromArgb(30,130,160); $btnMIRun.ForeColor = [System.Drawing.Color]::White; $btnMIRun.FlatStyle = 'Popup'
$btnCopyMIResults = New-Object System.Windows.Forms.Button
$btnCopyMIResults.Location = '610,160'; $btnCopyMIResults.Size = '110,30'; $btnCopyMIResults.Text = 'Copy Results'; $btnCopyMIResults.FlatStyle = 'Flat'; $btnCopyMIResults.BackColor = [System.Drawing.Color]::White; $btnCopyMIResults.Font = $uiFont
$btnOpenMIOutput = New-Object System.Windows.Forms.Button
$btnOpenMIOutput.Location = '726,160'; $btnOpenMIOutput.Size = '130,30'; $btnOpenMIOutput.Text = 'Open Output Folder'; $btnOpenMIOutput.FlatStyle = 'Flat'; $btnOpenMIOutput.BackColor = [System.Drawing.Color]::White; $btnOpenMIOutput.Font = $uiFont

$grpMI.Controls.AddRange(@($lblMIMode,$cmbMIMode,$lblMITargets,$txtMITargets,$lblMIOutCsv,$txtMIOutCsv,$btnBrowseMIOut,$lblMIListPath,$txtMIListPath,$btnBrowseMIList,$lblMIThrottle,$nudMIThrottle,$btnMIRun,$btnCopyMIResults,$btnOpenMIOutput))

# -- Machine Info: Output Paths Summary --
$grpMIArtifacts = New-Object System.Windows.Forms.GroupBox
$grpMIArtifacts.Text = 'Output Artifacts'; $grpMIArtifacts.Location = '6,220'; $grpMIArtifacts.Size = '952,50'; $grpMIArtifacts.Anchor = 'Top, Left, Right'; $grpMIArtifacts.Font = $emphasisFont
$lblMIArtifactSummary = New-Object System.Windows.Forms.Label
$lblMIArtifactSummary.Location = '10,20'; $lblMIArtifactSummary.Size = '930,22'; $lblMIArtifactSummary.Anchor = 'Top, Left, Right'; $lblMIArtifactSummary.Font = $monoFont; $lblMIArtifactSummary.Text = 'No run yet. Output CSV path and log location will appear here after a probe.'
$grpMIArtifacts.Controls.Add($lblMIArtifactSummary)

# -- Machine Info: Results pane --
$lblMIResults = New-Object System.Windows.Forms.Label
$lblMIResults.Location = '8,275'; $lblMIResults.Size = '140,18'; $lblMIResults.Text = 'Results'; $lblMIResults.Font = $emphasisFont
$txtMIResults = New-Object System.Windows.Forms.TextBox
$txtMIResults.Location = '6,295'; $txtMIResults.Size = '952,380'; $txtMIResults.Multiline = $true; $txtMIResults.ScrollBars = 'Both'; $txtMIResults.ReadOnly = $true; $txtMIResults.Anchor = 'Top, Bottom, Left, Right'; $txtMIResults.Font = $monoFont; $txtMIResults.WordWrap = $false; $txtMIResults.BackColor = [System.Drawing.Color]::White
$txtMIResults.Text = 'Enter targets above and click Run Probe, or load a host list file.'

$machineInfoTab.Controls.AddRange(@($grpMI,$grpMIArtifacts,$lblMIResults,$txtMIResults))

# -- Machine Info: dynamic default output path --
$cmbMIMode.Add_SelectedIndexChanged({
  if ($cmbMIMode.SelectedIndex -eq 0) {
    $txtMIOutCsv.Text = (Join-Path $repoRoot 'GetInfo\MachineInfo_Output.csv')
  } else {
    $txtMIOutCsv.Text = (Join-Path $repoRoot 'GetInfo\PrinterProbe_Output.csv')
  }
})

# -- Machine Info: Run handler --
$btnMIRun.Add_Click({
  try {
    # Gather targets from the textbox lines
    $inlineTargets = @($txtMITargets.Lines | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
    $listFile = $txtMIListPath.Text
    $hasListFile = ($listFile -and (Test-Path -LiteralPath $listFile))
    if (-not $inlineTargets.Count -and -not $hasListFile) { throw 'Enter at least one target or select a host list file.' }

    $outPath = $txtMIOutCsv.Text
    if ([string]::IsNullOrWhiteSpace($outPath)) { throw 'Select an output CSV path.' }
    $outDir = Split-Path -Parent $outPath
    if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    Set-StatusBarText -Category 'Running' -Message 'Machine Info probe in progress...'
    $txtMIResults.Text = 'Running...'
    [System.Windows.Forms.Application]::DoEvents()

    if ($cmbMIMode.SelectedIndex -eq 0) {
      # Get-MachineInfo -- requires a list file, so write inline targets to a temp file if needed
      $tempList = $null
      if ($hasListFile) {
        $actualListPath = $listFile
      } else {
        $tempList = Join-Path $env:TEMP ('MachineInfoTargets_{0}.txt' -f (Get-Date -Format 'yyyyMMddHHmmss'))
        $inlineTargets | Set-Content -LiteralPath $tempList -Encoding UTF8
        $actualListPath = $tempList
      }
      try {
        & $machineInfoScript -ListPath $actualListPath -OutputPath $outPath -Throttle ([int]$nudMIThrottle.Value) 2>&1 | Out-Null
      } finally {
        if ($tempList -and (Test-Path $tempList)) { Remove-Item $tempList -Force -ErrorAction SilentlyContinue }
      }
      if (Test-Path -LiteralPath $outPath) {
        $results = Import-Csv -LiteralPath $outPath
        $txtMIResults.Text = ($results | Format-Table -AutoSize | Out-String).Trim()
      } else {
        $txtMIResults.Text = 'Script completed but output CSV was not created. Check targets are reachable.'
      }
    } else {
      # Get-PrinterMacSerial
      $pmsArgs = @{}
      if ($hasListFile) {
        $pmsArgs['ListPath'] = $listFile
      } else {
        $pmsArgs['IPs'] = $inlineTargets
      }
      $pmsArgs['OutCsv'] = $outPath
      $pmsResults = & $printerMacScript @pmsArgs
      if ($pmsResults) {
        $txtMIResults.Text = ($pmsResults | Format-Table -AutoSize | Out-String).Trim()
      } elseif (Test-Path -LiteralPath $outPath) {
        $rows = Import-Csv -LiteralPath $outPath
        $txtMIResults.Text = ($rows | Format-Table -AutoSize | Out-String).Trim()
      } else {
        $txtMIResults.Text = 'Script completed but no results returned. Check targets are reachable.'
      }
    }

    $lblMIArtifactSummary.Text = "CSV: $outPath"
    if (Test-Path -LiteralPath $outPath) {
      $sz = [math]::Round((Get-Item $outPath).Length / 1KB, 1)
      $lblMIArtifactSummary.Text += "  ($sz KB)"
    }
    Set-StatusBarText -Category 'Done' -Message "Machine Info probe complete. Output: $outPath"
  } catch {
    $txtMIResults.Text = $_.Exception.Message
    Set-StatusBarText -Category 'Error' -Message 'Machine Info probe failed.'
  }
})

$btnCopyMIResults.Add_Click({
  try { Copy-TextToClipboard -Value $txtMIResults.Text -Label 'Machine Info results' }
  catch { Set-StatusBarText -Category 'Error' -Message 'Unable to copy results.' }
})
$btnOpenMIOutput.Add_Click({
  try {
    $outDir = Split-Path -Parent $txtMIOutCsv.Text
    if ($outDir -and (Test-Path -LiteralPath $outDir)) {
      Start-Process -FilePath 'explorer.exe' -ArgumentList @($outDir) | Out-Null
      Set-StatusBarText -Category 'Opened' -Message "Opened output folder: $outDir"
    } else { throw 'Output folder does not exist yet. Run a probe first.' }
  } catch {
    Set-StatusBarText -Category 'Error' -Message $_.Exception.Message
  }
})

# -- UTF-8 BOM Sync Tab --
$bomTab = New-Object System.Windows.Forms.TabPage
$bomTab.Text = 'UTF-8 BOM Sync'
$bomTab.BackColor = [System.Drawing.Color]::WhiteSmoke

# BOM scan state
$script:BomNeedFiles = [System.Collections.Generic.List[string]]::new()   # full paths -- no BOM
$script:BomHaveFiles = [System.Collections.Generic.List[string]]::new()   # full paths -- has BOM
$script:BomScanRoot  = $repoRoot

function Test-FileHasBom {
  param([string]$FilePath)
  $bytes = [System.IO.File]::ReadAllBytes($FilePath)
  return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Invoke-BomScan {
  $root = $txtBomRoot.Text
  if (-not $root -or -not (Test-Path -LiteralPath $root)) { throw 'Select a valid root directory to scan.' }
  $script:BomScanRoot = $root
  $script:BomNeedFiles.Clear()
  $script:BomHaveFiles.Clear()
  $lstBomNeed.Items.Clear()
  $lstBomHave.Items.Clear()

  $extensions = @('*.ps1','*.psm1','*.psd1','*.csv')
  $excludeDirs = @('.git','node_modules','__pycache__','Output','Archive','.vs','bin','obj')

  $files = foreach ($ext in $extensions) {
    Get-ChildItem -Path $root -Recurse -Filter $ext -File -ErrorAction SilentlyContinue
  }
  $files = $files | Where-Object {
    $rel = $_.FullName.Replace($root,'')
    $skip = $false
    foreach ($ex in $excludeDirs) {
      if ($rel -match "(^|[\\/])$([regex]::Escape($ex))([\\/]|$)") { $skip = $true; break }
    }
    -not $skip
  }

  foreach ($f in $files) {
    $rel = $f.FullName.Substring($root.Length).TrimStart('\','/')
    if (Test-FileHasBom -FilePath $f.FullName) {
      $script:BomHaveFiles.Add($f.FullName)
      [void]$lstBomHave.Items.Add($rel)
    } else {
      $script:BomNeedFiles.Add($f.FullName)
      [void]$lstBomNeed.Items.Add($rel)
    }
  }

  $lblBomNeedCount.Text = "Without BOM ($($lstBomNeed.Items.Count))"
  $lblBomHaveCount.Text = "With BOM ($($lstBomHave.Items.Count))"
  Set-StatusBarText -Category 'BOM Scan' -Message "Scanned $($lstBomNeed.Items.Count + $lstBomHave.Items.Count) file(s): $($lstBomNeed.Items.Count) need BOM, $($lstBomHave.Items.Count) already have BOM."
}

function Invoke-BomSync {
  if ($lstBomHave.Items.Count -eq 0) { throw 'Nothing to sync. Scan first, then move files to the right panel.' }
  $bomBytes = [byte[]](0xEF, 0xBB, 0xBF)
  $applied = 0
  # Apply BOM to every file in the right panel that doesn't already have one
  foreach ($fullPath in $script:BomHaveFiles) {
    if (-not (Test-Path -LiteralPath $fullPath)) { continue }
    if (Test-FileHasBom -FilePath $fullPath) { continue }
    $raw = [System.IO.File]::ReadAllBytes($fullPath)
    [System.IO.File]::WriteAllBytes($fullPath, ($bomBytes + $raw))
    $applied++
  }
  Set-StatusBarText -Category 'BOM Sync' -Message "Sync complete. BOM added to $applied file(s)."
  [System.Windows.Forms.MessageBox]::Show("UTF-8 BOM added to $applied file(s).`nFiles that already had BOM were skipped.", 'BOM Sync Complete', 'OK', 'Information') | Out-Null
  # Re-scan to refresh state
  Invoke-BomScan
}

# -- BOM Tab: Root path --
$grpBom = New-Object System.Windows.Forms.GroupBox
$grpBom.Text = 'UTF-8 BOM Sync'; $grpBom.Location = '6,6'; $grpBom.Size = '952,54'; $grpBom.Anchor = 'Top, Left, Right'; $grpBom.Font = $emphasisFont

$lblBomRoot = New-Object System.Windows.Forms.Label
$lblBomRoot.Location = '10,22'; $lblBomRoot.Size = '70,20'; $lblBomRoot.Text = 'Scan root'; $lblBomRoot.Font = $emphasisFont
$txtBomRoot = New-Object System.Windows.Forms.TextBox
$txtBomRoot.Location = '85,19'; $txtBomRoot.Size = '590,24'; $txtBomRoot.Text = $repoRoot; $txtBomRoot.Anchor = 'Top, Left, Right'; $txtBomRoot.Font = $uiFont
$btnBrowseBomRoot = New-Object System.Windows.Forms.Button
$btnBrowseBomRoot.Location = '681,18'; $btnBrowseBomRoot.Size = '30,26'; $btnBrowseBomRoot.Text = [char]0x2026; $btnBrowseBomRoot.Anchor = 'Top, Right'; $btnBrowseBomRoot.FlatStyle = 'Flat'; $btnBrowseBomRoot.Font = $uiFont
$btnBrowseBomRoot.Add_Click({ $p = Show-BrowseFolderDialog -Description 'Select folder to scan for BOM'; if ($p) { $txtBomRoot.Text = $p } })

$btnBomScan = New-Object System.Windows.Forms.Button
$btnBomScan.Location = '720,14'; $btnBomScan.Size = '110,34'; $btnBomScan.Text = [char]0x2315 + ' Scan'; $btnBomScan.Anchor = 'Top, Right'; $btnBomScan.FlatStyle = 'Popup'
$btnBomScan.Font = New-Object System.Drawing.Font('Segoe UI Bold',10); $btnBomScan.BackColor = [System.Drawing.Color]::FromArgb(30,130,160); $btnBomScan.ForeColor = [System.Drawing.Color]::White; $btnBomScan.Cursor = 'Hand'

$btnBomSync = New-Object System.Windows.Forms.Button
$btnBomSync.Location = '838,14'; $btnBomSync.Size = '105,34'; $btnBomSync.Anchor = 'Top, Right'; $btnBomSync.FlatStyle = 'Popup'
$btnBomSync.Text = [char]0x2714 + ' Sync'
$btnBomSync.Font = New-Object System.Drawing.Font('Segoe UI Bold',10); $btnBomSync.BackColor = [System.Drawing.Color]::FromArgb(30,150,30); $btnBomSync.ForeColor = [System.Drawing.Color]::White; $btnBomSync.Cursor = 'Hand'

$grpBom.Controls.AddRange(@($lblBomRoot,$txtBomRoot,$btnBrowseBomRoot,$btnBomScan,$btnBomSync))

# -- BOM Tab: Left (Need BOM) and Right (Have BOM) panels --
$lblBomNeedCount = New-Object System.Windows.Forms.Label
$lblBomNeedCount.Location = '8,68'; $lblBomNeedCount.Size = '380,20'; $lblBomNeedCount.Text = 'Without BOM (0)'; $lblBomNeedCount.Font = $emphasisFont
$lstBomNeed = New-Object System.Windows.Forms.ListBox
$lstBomNeed.Location = '6,90'; $lstBomNeed.Size = '405,560'; $lstBomNeed.Anchor = 'Top, Bottom, Left'; $lstBomNeed.Font = $monoFont; $lstBomNeed.SelectionMode = 'MultiExtended'; $lstBomNeed.HorizontalScrollbar = $true

$lblBomHaveCount = New-Object System.Windows.Forms.Label
$lblBomHaveCount.Location = '545,68'; $lblBomHaveCount.Size = '380,20'; $lblBomHaveCount.Text = 'With BOM (0)'; $lblBomHaveCount.Font = $emphasisFont
$lstBomHave = New-Object System.Windows.Forms.ListBox
$lstBomHave.Location = '543,90'; $lstBomHave.Size = '415,560'; $lstBomHave.Anchor = 'Top, Bottom, Left, Right'; $lstBomHave.Font = $monoFont; $lstBomHave.SelectionMode = 'MultiExtended'; $lstBomHave.HorizontalScrollbar = $true

# -- Move buttons between panels --
$btnBomMoveRight = New-Object System.Windows.Forms.Button
$btnBomMoveRight.Location = '418,220'; $btnBomMoveRight.Size = '118,36'; $btnBomMoveRight.Text = [char]0x25B6 + '  Move  ' + [char]0x25B6; $btnBomMoveRight.Font = $emphasisFont; $btnBomMoveRight.FlatStyle = 'Flat'; $btnBomMoveRight.BackColor = [System.Drawing.Color]::FromArgb(225,240,255); $btnBomMoveRight.Cursor = 'Hand'
$btnBomMoveLeft = New-Object System.Windows.Forms.Button
$btnBomMoveLeft.Location = '418,264'; $btnBomMoveLeft.Size = '118,36'; $btnBomMoveLeft.Text = [char]0x25C0 + '  Move  ' + [char]0x25C0; $btnBomMoveLeft.Font = $emphasisFont; $btnBomMoveLeft.FlatStyle = 'Flat'; $btnBomMoveLeft.BackColor = [System.Drawing.Color]::FromArgb(255,235,225); $btnBomMoveLeft.Cursor = 'Hand'
$btnBomMoveAllRight = New-Object System.Windows.Forms.Button
$btnBomMoveAllRight.Location = '418,316'; $btnBomMoveAllRight.Size = '118,36'; $btnBomMoveAllRight.Text = 'Move All  ' + [char]0x25B6 + [char]0x25B6; $btnBomMoveAllRight.Font = $emphasisFont; $btnBomMoveAllRight.FlatStyle = 'Flat'; $btnBomMoveAllRight.BackColor = [System.Drawing.Color]::FromArgb(200,230,255); $btnBomMoveAllRight.Cursor = 'Hand'

# -- Move selected items right (need → have) --
$btnBomMoveRight.Add_Click({
  $selected = @($lstBomNeed.SelectedIndices | Sort-Object -Descending)
  if (-not $selected.Count) { return }
  foreach ($i in $selected) {
    $rel = $lstBomNeed.Items[$i]
    $full = $script:BomNeedFiles[$i]
    $script:BomNeedFiles.RemoveAt($i)
    $lstBomNeed.Items.RemoveAt($i)
    $script:BomHaveFiles.Add($full)
    [void]$lstBomHave.Items.Add($rel)
  }
  $lblBomNeedCount.Text = "Without BOM ($($lstBomNeed.Items.Count))"
  $lblBomHaveCount.Text = "With BOM ($($lstBomHave.Items.Count))"
})

# -- Move selected items left (have → need) --
$btnBomMoveLeft.Add_Click({
  $selected = @($lstBomHave.SelectedIndices | Sort-Object -Descending)
  if (-not $selected.Count) { return }
  foreach ($i in $selected) {
    $rel = $lstBomHave.Items[$i]
    $full = $script:BomHaveFiles[$i]
    $script:BomHaveFiles.RemoveAt($i)
    $lstBomHave.Items.RemoveAt($i)
    $script:BomNeedFiles.Add($full)
    [void]$lstBomNeed.Items.Add($rel)
  }
  $lblBomNeedCount.Text = "Without BOM ($($lstBomNeed.Items.Count))"
  $lblBomHaveCount.Text = "With BOM ($($lstBomHave.Items.Count))"
})

# -- Move ALL left → right --
$btnBomMoveAllRight.Add_Click({
  while ($lstBomNeed.Items.Count -gt 0) {
    $rel = $lstBomNeed.Items[0]
    $full = $script:BomNeedFiles[0]
    $script:BomNeedFiles.RemoveAt(0)
    $lstBomNeed.Items.RemoveAt(0)
    $script:BomHaveFiles.Add($full)
    [void]$lstBomHave.Items.Add($rel)
  }
  $lblBomNeedCount.Text = "Without BOM ($($lstBomNeed.Items.Count))"
  $lblBomHaveCount.Text = "With BOM ($($lstBomHave.Items.Count))"
})

# -- Scan & Sync handlers --
$btnBomScan.Add_Click({
  try { Invoke-BomScan }
  catch {
    Set-StatusBarText -Category 'Error' -Message $_.Exception.Message
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'BOM Scan Error','OK','Warning') | Out-Null
  }
})

$btnBomSync.Add_Click({
  try {
    $confirm = [System.Windows.Forms.MessageBox]::Show("Apply UTF-8 BOM to all $($lstBomHave.Items.Count) file(s) in the right panel?`nFiles that already have BOM will be skipped.", 'Confirm BOM Sync', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { Set-StatusBarText -Category 'Cancelled' -Message 'BOM sync cancelled.'; return }
    Invoke-BomSync
  }
  catch {
    Set-StatusBarText -Category 'Error' -Message $_.Exception.Message
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'BOM Sync Error','OK','Warning') | Out-Null
  }
})

$bomTab.Controls.AddRange(@($grpBom,$lblBomNeedCount,$lstBomNeed,$lblBomHaveCount,$lstBomHave,$btnBomMoveRight,$btnBomMoveLeft,$btnBomMoveAllRight))

$tabs.TabPages.AddRange(@($runTab,$kronosTab,$machineInfoTab,$bomTab))
$form.Controls.Add($tabs)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.SizingGrip = $false
$script:StatusCategoryLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:StatusCategoryLabel.Text = 'Ready'
$script:StatusCategoryLabel.BorderSides = 'Right'
$script:StatusCategoryLabel.Font = $emphasisFont
$script:StatusMessageLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:StatusMessageLabel.Spring = $true
$script:StatusMessageLabel.TextAlign = 'MiddleLeft'
$script:StatusMessageLabel.Text = 'Dry-run defaults are preloaded. Start with -ListOnly -Preflight, then review the session outputs.'
$statusStrip.Items.AddRange(@($script:StatusCategoryLabel,$script:StatusMessageLabel))
$form.Controls.Add($statusStrip)

# -- Tutorial Overlay Panel --
$script:TutorialPanel = New-Object System.Windows.Forms.Panel
$script:TutorialPanel.Size = New-Object System.Drawing.Size(520,468)
$script:TutorialPanel.BackColor = [System.Drawing.Color]::FromArgb(30,42,56)
$script:TutorialPanel.BorderStyle = 'FixedSingle'
$script:TutorialPanel.Visible = $false
$script:TutorialPanel.Anchor = 'None'
$script:TutorialPanel.Cursor = [System.Windows.Forms.Cursors]::SizeAll

# -- Drag support for tutorial panel (works from any child control) --
$script:TutDragging = $false
$script:TutDragStart = [System.Drawing.Point]::Empty
$script:TutDragHandler_Down = {
  param($s,$e)
  if ($e.Button -eq 'Left') {
    $script:TutDragging = $true
    # Convert click point to panel-relative coords so any child can start a drag
    $script:TutDragStart = $script:TutorialPanel.PointToClient($s.PointToScreen($e.Location))
  }
}
$script:TutDragHandler_Move = {
  param($s,$e)
  if ($script:TutDragging) {
    $current = $script:TutorialPanel.PointToClient($s.PointToScreen($e.Location))
    $script:TutorialPanel.Left += $current.X - $script:TutDragStart.X
    $script:TutorialPanel.Top  += $current.Y - $script:TutDragStart.Y
  }
}
$script:TutDragHandler_Up = {
  param($s,$e)
  $script:TutDragging = $false
}
# Attach to the panel itself
$script:TutorialPanel.Add_MouseDown($script:TutDragHandler_Down)
$script:TutorialPanel.Add_MouseMove($script:TutDragHandler_Move)
$script:TutorialPanel.Add_MouseUp($script:TutDragHandler_Up)

$script:TutorialTitleLabel = New-Object System.Windows.Forms.Label
$script:TutorialTitleLabel.Location = '18,14'
$script:TutorialTitleLabel.Size = '440,28'
$script:TutorialTitleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold',13)
$script:TutorialTitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(230,240,255)
$script:TutorialTitleLabel.Text = ''
$script:TutorialTitleLabel.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$script:TutorialTitleLabel.Add_MouseDown($script:TutDragHandler_Down)
$script:TutorialTitleLabel.Add_MouseMove($script:TutDragHandler_Move)
$script:TutorialTitleLabel.Add_MouseUp($script:TutDragHandler_Up)

$btnTutorialClose = New-Object System.Windows.Forms.Button
$btnTutorialClose.Location = '480,8'
$btnTutorialClose.Size = '28,28'
$btnTutorialClose.Text = [char]0x2715
$btnTutorialClose.FlatStyle = 'Flat'
$btnTutorialClose.FlatAppearance.BorderSize = 0
$btnTutorialClose.Font = New-Object System.Drawing.Font('Segoe UI',11)
$btnTutorialClose.ForeColor = [System.Drawing.Color]::FromArgb(200,200,200)
$btnTutorialClose.BackColor = [System.Drawing.Color]::FromArgb(30,42,56)
$btnTutorialClose.Cursor = 'Hand'
$btnTutorialClose.Add_Click({ Hide-Tutorial })

$script:TutorialBodyLabel = New-Object System.Windows.Forms.Label
$script:TutorialBodyLabel.Location = '18,50'
$script:TutorialBodyLabel.Size = '484,260'
$script:TutorialBodyLabel.Font = New-Object System.Drawing.Font('Segoe UI',9.5)
$script:TutorialBodyLabel.ForeColor = [System.Drawing.Color]::FromArgb(210,220,235)
$script:TutorialBodyLabel.Text = ''
$script:TutorialBodyLabel.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$script:TutorialBodyLabel.Add_MouseDown($script:TutDragHandler_Down)
$script:TutorialBodyLabel.Add_MouseMove($script:TutDragHandler_Move)
$script:TutorialBodyLabel.Add_MouseUp($script:TutDragHandler_Up)

# -- Track selection buttons (visible only on the menu screen) --
$script:TrackButtons = @()
$trackBtnFont = New-Object System.Drawing.Font('Segoe UI Semibold',9.5)
$trackIdx = 0
foreach ($key in $script:TutorialTracks.Keys) {
  $track = $script:TutorialTracks[$key]
  $btn = New-Object System.Windows.Forms.Button
  $col = if ($trackIdx % 2 -eq 0) { 18 } else { 260 }
  $row = [Math]::Floor($trackIdx / 2)
  $btn.Location = New-Object System.Drawing.Point($col, (100 + $row * 52))
  $btn.Size = '232,44'
  $btn.Text = $track.Label + "`n" + $track.Desc
  $btn.TextAlign = 'MiddleLeft'
  $btn.Font = $trackBtnFont
  $btn.FlatStyle = 'Flat'
  $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80,100,130)
  $btn.BackColor = $track.Color
  $btn.ForeColor = [System.Drawing.Color]::White
  $btn.Cursor = 'Hand'
  $btn.Visible = $false
  $btn.Tag = $key
  $btn.Add_Click({ Start-TutorialTrack -TrackKey $this.Tag })
  $script:TrackButtons += $btn
  $script:TutorialPanel.Controls.Add($btn)
  $trackIdx++
}

# -- Step navigation buttons --
$script:TutorialBtnPrev = New-Object System.Windows.Forms.Button
$script:TutorialBtnPrev.Location = '18,420'
$script:TutorialBtnPrev.Size = '60,32'
$script:TutorialBtnPrev.Text = [char]0x2190 + ' Prev'
$script:TutorialBtnPrev.FlatStyle = 'Flat'
$script:TutorialBtnPrev.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80,100,130)
$script:TutorialBtnPrev.ForeColor = [System.Drawing.Color]::White
$script:TutorialBtnPrev.BackColor = [System.Drawing.Color]::FromArgb(50,65,85)
$script:TutorialBtnPrev.Font = $uiFont
$script:TutorialBtnPrev.Cursor = 'Hand'
$script:TutorialBtnPrev.Visible = $false
$script:TutorialBtnPrev.Add_Click({
  if ($script:TutorialIndex -gt 0) { $script:TutorialIndex--; Update-TutorialView }
})

$script:TutorialCounter = New-Object System.Windows.Forms.Label
$script:TutorialCounter.Location = '140,426'
$script:TutorialCounter.Size = '120,20'
$script:TutorialCounter.TextAlign = 'MiddleCenter'
$script:TutorialCounter.Font = $uiFont
$script:TutorialCounter.ForeColor = [System.Drawing.Color]::FromArgb(160,175,195)
$script:TutorialCounter.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$script:TutorialCounter.Add_MouseDown($script:TutDragHandler_Down)
$script:TutorialCounter.Add_MouseMove($script:TutDragHandler_Move)
$script:TutorialCounter.Add_MouseUp($script:TutDragHandler_Up)

# Menu button -- returns to the track picker from inside a track
$script:TutorialBtnMenu = New-Object System.Windows.Forms.Button
$script:TutorialBtnMenu.Location = '270,420'
$script:TutorialBtnMenu.Size = '80,32'
$script:TutorialBtnMenu.Text = [char]0x2302 + ' Menu'
$script:TutorialBtnMenu.FlatStyle = 'Flat'
$script:TutorialBtnMenu.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80,100,130)
$script:TutorialBtnMenu.ForeColor = [System.Drawing.Color]::White
$script:TutorialBtnMenu.BackColor = [System.Drawing.Color]::FromArgb(70,85,110)
$script:TutorialBtnMenu.Font = $uiFont
$script:TutorialBtnMenu.Cursor = 'Hand'
$script:TutorialBtnMenu.Visible = $false
$script:TutorialBtnMenu.Add_Click({ Show-TutorialMenu })

$script:TutorialBtnNext = New-Object System.Windows.Forms.Button
$script:TutorialBtnNext.Location = '440,420'
$script:TutorialBtnNext.Size = '60,32'
$script:TutorialBtnNext.Text = 'Next ' + [char]0x2192
$script:TutorialBtnNext.FlatStyle = 'Flat'
$script:TutorialBtnNext.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80,100,130)
$script:TutorialBtnNext.ForeColor = [System.Drawing.Color]::White
$script:TutorialBtnNext.BackColor = [System.Drawing.Color]::FromArgb(50,65,85)
$script:TutorialBtnNext.Font = $uiFont
$script:TutorialBtnNext.Cursor = 'Hand'
$script:TutorialBtnNext.Visible = $false
$script:TutorialBtnNext.Add_Click({
  if ($script:TutorialIndex -lt ($script:TutorialSteps.Count - 1)) { $script:TutorialIndex++; Update-TutorialView }
})

$script:TutorialPanel.Controls.AddRange(@(
  $script:TutorialTitleLabel, $btnTutorialClose, $script:TutorialBodyLabel,
  $script:TutorialBtnPrev, $script:TutorialCounter, $script:TutorialBtnMenu, $script:TutorialBtnNext
))
$form.Controls.Add($script:TutorialPanel)
$script:TutorialPanel.BringToFront()

# Center the tutorial panel on form resize / load
$centerTutorial = {
  $script:TutorialPanel.Left = [Math]::Max(0, [int](($form.ClientSize.Width - $script:TutorialPanel.Width) / 2))
  $script:TutorialPanel.Top  = [Math]::Max(0, [int](($form.ClientSize.Height - $script:TutorialPanel.Height) / 2))
}
$form.Add_Resize($centerTutorial)
$form.Add_Shown({
  & $centerTutorial
  Show-TutorialAtCheckpoint -CheckpointName 'FirstLaunch' -StepIndex 0
})

# -- Tutorial Relaunch Button (on status strip) --
$btnShowTutorial = New-Object System.Windows.Forms.ToolStripButton
$btnShowTutorial.Text = 'Tutorial (Ctrl+T)'
$btnShowTutorial.DisplayStyle = 'Text'
$btnShowTutorial.Alignment = 'Right'
$btnShowTutorial.Add_Click({ if ($script:TutorialActive) { Hide-Tutorial } else { Show-Tutorial } })
$statusStrip.Items.Add($btnShowTutorial) | Out-Null

$toolTip.SetToolTip($btnStop,'Request a graceful stop using the selected stop-signal file. (Ctrl+S)')
$toolTip.SetToolTip($btnStatus,'Refresh the current status snapshot from disk. (F5)')
$toolTip.SetToolTip($btnLoad,'Load the current undo/redo session summary from disk. (Ctrl+L)')
$toolTip.SetToolTip($txtRunTargets,'One hostname per line for controller mode.')
$toolTip.SetToolTip($cmbRunMode,'Select the worker run mode. Recon Only is the safest starting point.')
$toolTip.SetToolTip($chkPreflight,'Run preflight checks before executing any changes.')
$toolTip.SetToolTip($chkRestartSpooler,'Restart the print spooler service if needed after changes.')
$toolTip.SetToolTip($txtQueuesAdd,'UNC queue paths to add machine-wide (one per line).')
$toolTip.SetToolTip($txtQueuesRemove,'UNC queue paths to remove machine-wide (one per line).')
$toolTip.SetToolTip($txtDefaultQueue,'Optional: set this queue as the default for users at next logon.')
$toolTip.SetToolTip($txtWorkerOptions,'Auto-generated worker argument string from the controls above.')
$toolTip.SetToolTip($btnExampleOptions,'Load a pragmatic example that keeps the worker in dry-run/preflight mode. (Ctrl+E)')
$toolTip.SetToolTip($btnOpenSession,'Open the most recent GUI run folder in Explorer.')
$toolTip.SetToolTip($btnCopyStatus,'Copy the status pane text to the clipboard.')
$toolTip.SetToolTip($btnCopyHistory,'Copy the history pane text to the clipboard.')
$toolTip.SetToolTip($chkAutoRefresh,'Automatically refresh status and history while the Run Control tab is active.')
$toolTip.SetToolTip($nudRefreshSeconds,'How often the GUI should auto refresh run status and history.')
$toolTip.SetToolTip($btnCopyClockResults,'Copy the Kronos results pane to the clipboard.')
$toolTip.SetToolTip($btnBrowseStop,'Browse for a stop-signal JSON file.')
$toolTip.SetToolTip($btnBrowseStatus,'Browse for a status snapshot JSON file.')
$toolTip.SetToolTip($btnBrowseHistory,'Browse for an undo/redo history JSON file.')
$toolTip.SetToolTip($btnBrowseClockOut,'Browse for an output CSV path.')
$toolTip.SetToolTip($txtStop,'Click to browse for a stop-signal file.')
$toolTip.SetToolTip($txtStatus,'Click to browse for a status snapshot file.')
$toolTip.SetToolTip($txtUndo,'Click to browse for an undo/redo history file.')
$toolTip.SetToolTip($txtClockOut,'Click to browse for an output CSV path.')
$toolTip.SetToolTip($txtInv,'Click to browse for an inventory CSV file.')
$toolTip.SetToolTip($btnBrowseInv,'Browse for an inventory CSV file.')
$toolTip.SetToolTip($btnUndo,'Replay the top undo action. (Ctrl+Z)')
$toolTip.SetToolTip($btnRedo,'Replay the top redo action. (Ctrl+Y)')
$toolTip.SetToolTip($btnBomScan,'Scan the root directory for files with and without UTF-8 BOM.')
$toolTip.SetToolTip($btnBomSync,'Apply UTF-8 BOM to all files in the right panel.')
$toolTip.SetToolTip($btnBomMoveRight,'Move selected files from the left panel (no BOM) to the right panel (will get BOM on sync).')
$toolTip.SetToolTip($btnBomMoveLeft,'Move selected files back to the left panel (will not get BOM on sync).')
$toolTip.SetToolTip($btnBomMoveAllRight,'Move ALL files from left to right so they all get BOM on sync.')
$toolTip.SetToolTip($txtBomRoot,'Root directory to scan for PowerShell and CSV files.')

# -- Browse button handlers --
$btnBrowseStop.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select stop-signal file'; if ($p) { $txtStop.Text = $p } })
$btnBrowseStatus.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select status snapshot file'; if ($p) { $txtStatus.Text = $p } })
$btnBrowseHistory.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select undo/redo history file'; if ($p) { $txtUndo.Text = $p } })
$btnBrowseClockOut.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select output CSV path' -Filter 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'; if ($p) { $txtClockOut.Text = $p } })
$btnBrowseInv.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select inventory CSV file' -Filter 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'; if ($p) { $txtInv.Text = $p } })

# -- Click-to-browse on path text fields --
$txtStop.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select stop-signal file'; if ($p) { $txtStop.Text = $p } })
$txtStatus.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select status snapshot file'; if ($p) { $txtStatus.Text = $p } })
$txtUndo.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select undo/redo history file'; if ($p) { $txtUndo.Text = $p } })
$txtClockOut.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select output CSV path' -Filter 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'; if ($p) { $txtClockOut.Text = $p } })
$txtInv.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select inventory CSV file' -Filter 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'; if ($p) { $txtInv.Text = $p } })

# -- Keyboard shortcuts (KeyDown on the form with KeyPreview) --
$form.Add_KeyDown({
  param($formSender, $e)
  # Tutorial navigation takes priority when active
  if ($script:TutorialActive -and -not $script:TutorialInMenu) {
    if ($e.KeyCode -eq 'Left')   { $script:TutorialBtnPrev.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true; return }
    if ($e.KeyCode -eq 'Right')  { $script:TutorialBtnNext.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true; return }
    if ($e.KeyCode -eq 'Escape') { Show-TutorialMenu; $e.Handled = $true; $e.SuppressKeyPress = $true; return }
  } elseif ($script:TutorialActive -and $script:TutorialInMenu) {
    if ($e.KeyCode -eq 'Escape') { Hide-Tutorial; $e.Handled = $true; $e.SuppressKeyPress = $true; return }
  }
  if ($e.Control -and $e.KeyCode -eq 'T') {
    if ($script:TutorialActive) { Hide-Tutorial } else { Show-Tutorial }
    $e.Handled = $true; $e.SuppressKeyPress = $true
  }
  elseif ($e.Control -and $e.KeyCode -eq 'S') { $btnStop.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.KeyCode -eq 'F5') { $btnStatus.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.Control -and $e.KeyCode -eq 'L') { $btnLoad.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.Control -and $e.KeyCode -eq 'Z') { $btnUndo.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.Control -and $e.KeyCode -eq 'Y') { $btnRedo.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.Control -and $e.KeyCode -eq 'E') { $btnExampleOptions.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
})

# -- Button click handlers (with confirmation dialogs for destructive actions) --
$btnStop.Add_Click({
  try {
    if ([string]::IsNullOrWhiteSpace($txtStop.Text)) { throw 'The stop-signal path is empty. Browse or type a valid path first.' }
    $confirm = [System.Windows.Forms.MessageBox]::Show('Are you sure you want to send a stop signal to the running session?','Confirm Stop','YesNo','Question')
    if ($confirm -ne 'Yes') { Set-StatusBarText -Category 'Cancelled' -Message 'Stop request cancelled.'; return }
    $signal = Request-RunStop -Path $txtStop.Text -Reason 'GUI stop button pressed'
    Set-StatusBarText -Category 'Stopping' -Message 'Stop request was written successfully.'
    [System.Windows.Forms.MessageBox]::Show((Format-ObjectText $signal),'Stop requested','OK','Information') | Out-Null
  } catch {
    Set-StatusBarText -Category 'Error' -Message 'Failed to write the stop request.'
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Stop failed','OK','Warning') | Out-Null
  }
})

$btnStatus.Add_Click({ Refresh-RunStatusView })
$btnLoad.Add_Click({ Refresh-RunHistoryView })
$btnExampleOptions.Add_Click({ Load-SafeWorkerExample })

$btnOpenSession.Add_Click({
  try { Open-RunSessionFolder }
  catch {
    Set-StatusBarText -Category 'Error' -Message 'Unable to open the current session folder.'
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Open session folder failed','OK','Warning') | Out-Null
  }
})

$btnCopyStatus.Add_Click({
  try { Copy-TextToClipboard -Value $txtStatusView.Text -Label 'Status view' }
  catch {
    Set-StatusBarText -Category 'Error' -Message 'Unable to copy the status pane.'
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Copy status failed','OK','Warning') | Out-Null
  }
})

$btnCopyHistory.Add_Click({
  try { Copy-TextToClipboard -Value $txtHistoryView.Text -Label 'History view' }
  catch {
    Set-StatusBarText -Category 'Error' -Message 'Unable to copy the history pane.'
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Copy history failed','OK','Warning') | Out-Null
  }
})

$btnUndo.Add_Click({
  try {
    if (-not $script:LoadedSession) { throw 'Load an undo/redo session first.' }
    $result = Replay-UndoRedoAction -Session $script:LoadedSession -Operation Undo -WhatIf:$chkWhatIf.Checked
    $txtHistoryView.Text = (Format-UndoRedoText $script:LoadedSession) + [Environment]::NewLine + [Environment]::NewLine + (Format-ObjectText $result)
    Set-StatusBarText -Category 'Undo' -Message 'Executed the top undo action.'
    Update-RunActionState
  } catch {
    Set-StatusBarText -Category 'Error' -Message 'Undo replay failed.'
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Undo failed','OK','Warning') | Out-Null
  }
})

$btnRedo.Add_Click({
  try {
    if (-not $script:LoadedSession) { throw 'Load an undo/redo session first.' }
    $result = Replay-UndoRedoAction -Session $script:LoadedSession -Operation Redo -WhatIf:$chkWhatIf.Checked
    $txtHistoryView.Text = (Format-UndoRedoText $script:LoadedSession) + [Environment]::NewLine + [Environment]::NewLine + (Format-ObjectText $result)
    Set-StatusBarText -Category 'Redo' -Message 'Executed the top redo action.'
    Update-RunActionState
  } catch {
    Set-StatusBarText -Category 'Error' -Message 'Redo replay failed.'
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Redo failed','OK','Warning') | Out-Null
  }
})

$btnStartWorker.Add_Click({
  try {
    $confirm = [System.Windows.Forms.MessageBox]::Show("Launch a local Worker run with the current options?`n`nOptions: $($txtWorkerOptions.Text)",'Confirm Worker Launch','YesNo','Question')
    if ($confirm -ne 'Yes') { Set-StatusBarText -Category 'Cancelled' -Message 'Worker launch cancelled.'; return }
    Start-GuiRun -Mode Worker
  } catch {
    Set-StatusBarText -Category 'Error' -Message 'Local worker launch failed.'
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Local worker start failed','OK','Error') | Out-Null
  }
})

$btnStartController.Add_Click({
  try {
    $targets = Get-TrimmedLines -Lines $txtRunTargets.Lines
    if (-not $targets.Count) { throw 'Enter at least one controller target hostname before launching.' }
    $confirm = [System.Windows.Forms.MessageBox]::Show("Launch a Controller run targeting $($targets.Count) host(s)?`n`nTargets: $($targets -join ', ')",'Confirm Controller Launch','YesNo','Question')
    if ($confirm -ne 'Yes') { Set-StatusBarText -Category 'Cancelled' -Message 'Controller launch cancelled.'; return }
    Start-GuiRun -Mode Controller
  } catch {
    Set-StatusBarText -Category 'Error' -Message 'Controller launch failed.'
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Controller start failed','OK','Error') | Out-Null
  }
})

$btnProbe.Add_Click({
  try {
    $targets = @($txtTargets.Lines | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
    if (-not $targets.Count) { throw 'Enter at least one IP or hostname.' }
    $results = & $kronosScript -Targets $targets -OutCsv $txtClockOut.Text
    $txtInv.Text = $txtClockOut.Text
    $txtClockResults.Text = Format-ObjectText @($results)
    Set-StatusBarText -Category 'Probe' -Message "Probed $($targets.Count) target(s) and refreshed the inventory path."
  } catch {
    $txtClockResults.Text = $_.Exception.Message
    Set-StatusBarText -Category 'Error' -Message 'Kronos probe failed.'
  }
})

$btnInventory.Add_Click({
  try {
    $txtClockResults.Text = Format-ObjectText @(& $kronosScript -InventoryPath $txtInv.Text)
    Set-StatusBarText -Category 'Inventory' -Message 'Loaded inventory results from disk.'
  } catch {
    $txtClockResults.Text = $_.Exception.Message
    Set-StatusBarText -Category 'Error' -Message 'Loading the inventory file failed.'
  }
})

$btnFind.Add_Click({
  try {
    $terms = @($txtLookup.Text -split '[,;\r\n]+' | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
    if (-not $terms.Count) { throw 'Enter a lookup value.' }
    $txtClockResults.Text = Format-ObjectText @(& $kronosScript -InventoryPath $txtInv.Text -LookupBy $cmbLookup.SelectedItem -LookupValue $terms)
    Set-StatusBarText -Category 'Lookup' -Message "Searched the inventory using $($cmbLookup.SelectedItem) for $($terms.Count) value(s)."
  } catch {
    $txtClockResults.Text = $_.Exception.Message
    Set-StatusBarText -Category 'Error' -Message 'Inventory lookup failed.'
  }
})

$btnCopyClockResults.Add_Click({
  try { Copy-TextToClipboard -Value $txtClockResults.Text -Label 'Kronos results' }
  catch {
    Set-StatusBarText -Category 'Error' -Message 'Unable to copy the Kronos results pane.'
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Copy results failed') | Out-Null
  }
})

$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = [int]$nudRefreshSeconds.Value * 1000
$refreshTimer.Add_Tick({
  try {
    if (-not $chkAutoRefresh.Checked) { return }
    if ($tabs.SelectedTab -ne $runTab) { return }
    Refresh-RunStatusView
    Refresh-RunHistoryView
  } catch [System.Management.Automation.PipelineStoppedException] { <# Ctrl+C in host — ignore #> }
})
$nudRefreshSeconds.Add_ValueChanged({
  $refreshTimer.Interval = [int]$nudRefreshSeconds.Value * 1000
  Set-StatusBarText -Category 'Auto refresh' -Message "Auto refresh interval set to $($nudRefreshSeconds.Value) second(s)."
})
$refreshTimer.Start()
$form.Add_FormClosed({ $refreshTimer.Stop(); $script:GlowTimer.Stop() })
Update-RunActionState

# -- Tutorial checkpoint on tab change (menu-based: no auto-jump) --

# Defense-in-depth: swallow PipelineStoppedException so Ctrl+C in the host
# console never surfaces the .NET unhandled-exception dialog.
[System.Windows.Forms.Application]::add_ThreadException({
  param($eventSender, $e)
  if ($e.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }
  [System.Windows.Forms.MessageBox]::Show(
    $e.Exception.Message, 'SysAdminSuite Error',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
})
[System.Windows.Forms.Application]::SetUnhandledExceptionMode(
  [System.Windows.Forms.UnhandledExceptionMode]::CatchException)

[void]$form.ShowDialog()