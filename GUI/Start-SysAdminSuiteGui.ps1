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
    $txtStatusView.Text = Format-ObjectText (Import-RunStatusSnapshot -Path $txtStatus.Text)
    Set-StatusBarText -Category 'Refreshed' -Message "Loaded status snapshot from $($txtStatus.Text)"
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

# ── Tutorial System ──
$script:TutorialSteps = @(
  @{ Title = 'Welcome to SysAdminSuite'; Highlights = @(); Body = "SysAdminSuite is a portable toolkit for Windows sysadmins. It includes:`n`n- Printer Mapping: push/remove machine-wide printer queues across hosts`n- Kronos Clock Inventory: probe network clocks by IP, get MAC/serial/model`n- Software Inventory: scan ARP registry for installed apps (Config folder)`n- Shortcut Deployment: push desktop shortcuts to workstations (EnvSetup)`n- OCR Tools: extract printer labels from photos (OCR folder, Python)`n- AD Group Management: bulk-add computers to print groups`n`nThis GUI covers Printer Mapping and Kronos. Use arrow keys or buttons to continue." }
  @{ Title = 'How to Launch This GUI'; Highlights = @(); Body = "You are already running the GUI! For future reference, open PowerShell and run:`n`n  powershell.exe -STA -File .\\GUI\\Start-SysAdminSuiteGui.ps1`n`nThe -STA flag is required for WinForms. Run from the repo root so all paths resolve correctly.`n`nTip: Pin this shortcut to your taskbar on every admin box, then git pull to stay current." }
  @{ Title = 'Quick Start: Your First Recon Run'; Highlights = @('btnExampleOptions'); Body = "Let's do a safe dry run right now. Click the highlighted Load Safe Example button.`n`nThis pre-fills Recon Only + Preflight mode, which snapshots existing printers without making any changes. It is completely safe to run on production machines.`n`nTry it now, then click Next to continue." }
  @{ Title = 'Session Paths - Click to Browse'; Highlights = @('grpPaths','txtStop','txtStatus','txtUndo'); Body = "These three paths point to your run session files:`n`n- Stop signal: write here to gracefully stop a running job`n- Status path: the live status snapshot from the worker`n- History path: the undo/redo change log`n`nClick any highlighted text field to open a file browser, or use the [...] buttons on the right. Defaults point to Mapping\\Output in the repo." }
  @{ Title = 'Session Paths - Stop and Refresh'; Highlights = @('btnStop','btnBrowseStop','btnStatus','btnLoad'); Body = "The action buttons on the right side of each row:`n`n- Stop Run (Ctrl+S): writes a stop signal so a running worker exits gracefully`n- Refresh Now (F5): reloads the status snapshot from disk`n- Load History (Ctrl+L): imports the undo/redo session for replay`n`nTry clicking Refresh Now -- it is safe even with no active run." }
  @{ Title = 'Run Options - Safety First'; Highlights = @('grpOptions','chkWhatIf','chkAutoRefresh'); Body = "WhatIf replay (highlighted) keeps undo/redo in dry-run mode. Leave it checked until you have reviewed the output and are confident in the changes.`n`nAuto refresh polls status and history on a timer so you do not have to keep clicking Refresh.`n`nRule of thumb: always start with WhatIf ON. Turn it off only when you are ready to commit." }
  @{ Title = 'Undo and Redo'; Highlights = @('btnUndo','btnRedo'); Body = "After loading a history file, these buttons let you step through changes:`n`n- Undo Top (Ctrl+Z): reverses the most recent action`n- Redo Top (Ctrl+Y): re-applies it`n`nWith WhatIf checked, undo/redo only previews what would happen. Uncheck WhatIf to execute for real.`n`nTry it: Load History first, then click Undo Top to see a preview." }
  @{ Title = 'Launch Config - Run Mode'; Highlights = @('cmbRunMode','chkPreflight','chkRestartSpooler'); Body = "The Run Mode dropdown controls what the worker does:`n`n- Recon Only (-ListOnly): snapshot printers, zero changes`n- Plan Only (-PlanOnly): report what would change, no execution`n- Full Run: execute adds and removes`n- Full Run + Prune: also remove queues not in your list`n`nPreflight runs pre-checks. Restart Spooler restarts the print spooler after changes (use sparingly)." }
  @{ Title = 'Launch Config - Targets and Queues'; Highlights = @('txtRunTargets','txtQueuesAdd','txtQueuesRemove','txtDefaultQueue'); Body = "Fill in the highlighted fields to define your run:`n`n- Controller targets (left): hostnames to push to, one per line`n  Example: WKS001`n- Queues to Add: UNC paths like \\\\PRINTSRV\\QueueName`n- Queues to Remove: UNC paths to delete machine-wide`n- Default Queue: optionally set a user default at next logon`n`nThe Generated Options line at the bottom auto-builds the CLI string." }
  @{ Title = 'Launch Config - Start the Run'; Highlights = @('btnStartWorker','btnStartController'); Body = "Two ways to launch:`n`n- Start Local Worker (blue): runs the mapping on THIS machine only. Good for testing on your own box.`n- Start Controller (green): fans out to every host listed in the targets box via SMB + scheduled tasks. This is the production path.`n`nBoth will ask for confirmation before starting. Output appears in the Status pane below.`n`nTry it: with Recon Only selected, click Start Local Worker to see your own printers." }
  @{ Title = 'Status and History Panes'; Highlights = @('txtStatusView','txtHistoryView','btnCopyStatus','btnCopyHistory'); Body = "After a run starts, live data appears here:`n`n- Run Status: the latest worker status snapshot`n- Undo/Redo History: a timestamped change log`n`nClick Copy Status or Copy History to grab text for tickets or reports.`n`nTip: Open Session Folder opens the run output directory in Explorer so you can inspect CSV/HTML artifacts directly." }
  @{ Title = 'Example: Recon Run Output'; Highlights = @('txtStatusView'); Body = "After clicking Start Local Worker with Recon Only, the Status pane shows:`n`n  {`n    ""State"":  ""Completed"",`n    ""Stage"":  ""ListOnly"",`n    ""Message"": ""ListOnly inventory completed."",`n    ""Data"": {`n      ""ComputerName"": ""YOURPC"",`n      ""ListOnly"": true,`n      ""DesiredQueues"": []`n    }`n  }`n`nThis confirms the worker ran, found your printers, and wrote artifacts to disk. No changes were made." }
  @{ Title = 'Example: Recon Results on Disk'; Highlights = @('btnOpenSession'); Body = "Click Open Session Folder to see the artifacts the worker wrote:`n`n  Mapping\\Output\\20260324-143022\\`n    Run.log          - full transcript of the worker run`n    Preflight.csv    - snapshot of printers before any changes`n    Results.csv      - final state (Type, Target, Status)`n    Results.html     - browser-friendly report with a dark theme`n`nOpen Results.html in a browser for a quick visual audit. The CSV columns are:`n`n  Timestamp | ComputerName | Type | Target | Driver | Port | Status`n  (UNC and LOCAL rows, all marked PresentNow in Recon mode)" }
  @{ Title = 'Example: Full Run Output'; Highlights = @('txtStatusView'); Body = "If you switch Run Mode to Full Run and add a queue like:`n`n  \\\\PRINTSRV\\Lobby-HP4050`n`nthe Results.csv will show rows like:`n`n  Type   Target                     Status`n  ----   ------                     ------`n  UNC    \\\\printsrv\\lobby-hp4050   Added`n  UNC    \\\\printsrv\\office-hp5550  PresentBefore`n  LOCAL  Microsoft Print to PDF     PresentAfter`n`nAdded = newly mapped. PresentBefore = already existed. Removed = deleted by you.`nAlways run Recon first, review Results.csv, then switch to Full Run." }
  @{ Title = 'Kronos - Enter Targets and Probe'; Highlights = @('txtTargets','btnProbe','txtClockOut'); Body = "Switch to the Kronos Lookup tab to inventory network clocks.`n`n1. Type IP addresses or hostnames in the Targets box, one per line`n   Example: 10.1.2.50`n2. Set the Output CSV path (click the field to browse)`n3. Click Probe Targets to scan via ICMP, SNMP, ARP, HTTP, and DNS`n`nThe probe collects MAC, serial, model, firmware, and hostname for each device." }
  @{ Title = 'Example: Kronos Probe Output'; Highlights = @('txtClockResults'); Body = "After probing, the Results pane shows a table like:`n`n  QueryInput  IPAddress   HostName       MACAddress         Serial   Reachable`n  ----------  ---------   --------       ----------         ------   ---------`n  10.1.2.50   10.1.2.50   KRON-CLK-01    00:1A:2B:3C:4D:5E  KRN4401  True`n  10.1.2.51   10.1.2.51   KRON-CLK-02    00:1A:2B:3C:4D:5F  KRN4402  True`n  badhost     (none)      badhost        (none)             (none)   False`n`nReachable=True means the clock responded to ICMP. MAC/Serial come from SNMP and ARP.`nThe same data is saved to the Output CSV for use in Excel or DHCP reservation forms." }
  @{ Title = 'Kronos - Load and Search Inventory'; Highlights = @('btnInventory','cmbLookup','txtLookup','btnFind'); Body = "Already have a saved CSV? Click Load Inventory to import it without re-probing.`n`nTo search the loaded data:`n1. Pick a field from the dropdown: IP, MAC, Serial, HostName, DeviceName, or Any`n2. Type a value in the search box (partial matches work with Any)`n3. Click Find Match`n`nTry it: after probing, type a known IP and click Find Match to look it up." }
  @{ Title = 'Example: Kronos Search Result'; Highlights = @('txtClockResults','btnCopyClockResults'); Body = "After searching by MAC for 00:1A:2B:3C:4D:5E, the Results pane narrows to:`n`n  QueryInput  IPAddress   HostName       MACAddress         Serial   Reachable`n  ----------  ---------   --------       ----------         ------   ---------`n  10.1.2.50   10.1.2.50   KRON-CLK-01    00:1A:2B:3C:4D:5E  KRN4401  True`n`nThis is the cross-lookup workflow: start with one identifier (MAC, serial, IP, or hostname) and get back the full identity record.`n`nClick Copy Results to paste into a ticket or DHCP reservation form." }
  @{ Title = 'Kronos - Results and Export'; Highlights = @('txtClockResults','btnCopyClockResults'); Body = "All probe, inventory, and search results appear in the Results pane.`n`nClick Copy Results to copy the full text to your clipboard for pasting into tickets, spreadsheets, or DHCP reservation forms.`n`nThe Output CSV is also saved to disk automatically after each probe, so you can open it in Excel or re-import it later." }
  @{ Title = 'Beyond This GUI'; Highlights = @(); Body = "This GUI covers Printer Mapping and Kronos, but the suite has more:`n`n- Config\\Inventory-Software.ps1: scan installed apps across hosts`n- Config\\Fetch-Installers.ps1: download vendor installers from sources.csv`n- Config\\Stage-To-Clients.ps1: push a software repo to client PCs`n- EnvSetup\\Deploy-Shortcuts.ps1: deploy desktop shortcuts to workstations`n- OCR\\locus_mapping_ocr.py: extract printer labels from photos`n- ActiveDirectory\\Add-Computers-To-PrintingGroup.ps1: bulk AD updates`n`nRun any script with -WhatIf or -DryRun first. Check README.md for full docs." }
  @{ Title = 'Keyboard Shortcuts'; Highlights = @(); Body = "Speed up your workflow with these shortcuts:`n`n  Ctrl+S  -  Send stop signal`n  F5  -  Refresh status`n  Ctrl+L  -  Load history`n  Ctrl+Z / Ctrl+Y  -  Undo / Redo`n  Ctrl+E  -  Load safe example options`n  Ctrl+T  -  Show/hide this tutorial`n`nYou are all set! Close this tutorial and try a Recon run to get started." }
)
$script:TutorialIndex = 0
$script:TutorialActive = $false
$script:TutorialShownOnce = $false
$script:TutorialCheckpoints = @{}
$script:HighlightColor = [System.Drawing.Color]::FromArgb(70,130,240)
$script:HighlightedControls = @()

function Clear-TutorialHighlight {
  foreach ($entry in $script:HighlightedControls) {
    $ctrl = $entry.Control
    if ($null -ne $entry.BackColor) { $ctrl.BackColor = $entry.BackColor }
    if ($null -ne $entry.ForeColor) { $ctrl.ForeColor = $entry.ForeColor }
  }
  $script:HighlightedControls = @()
}

function Apply-TutorialHighlights {
  param([string[]]$Names)
  Clear-TutorialHighlight
  if (-not $Names -or $Names.Count -eq 0) { return }
  $list = [System.Collections.Generic.List[psobject]]::new()
  foreach ($name in $Names) {
    if (-not $name) { continue }
    $ctrl = Get-Variable -Name $name -ValueOnly -ErrorAction SilentlyContinue
    if (-not $ctrl) { continue }
    $entry = [pscustomobject]@{ Control = $ctrl; BackColor = $ctrl.BackColor; ForeColor = $ctrl.ForeColor }
    $list.Add($entry)
    if ($ctrl -is [System.Windows.Forms.GroupBox]) {
      $ctrl.BackColor = [System.Drawing.Color]::FromArgb(220,232,255)
      $ctrl.ForeColor = $script:HighlightColor
    } elseif ($ctrl -is [System.Windows.Forms.Button]) {
      $ctrl.BackColor = [System.Drawing.Color]::FromArgb(180,210,255)
    } elseif ($ctrl -is [System.Windows.Forms.TextBox]) {
      $ctrl.BackColor = [System.Drawing.Color]::FromArgb(230,240,255)
    } elseif ($ctrl -is [System.Windows.Forms.ComboBox]) {
      $ctrl.BackColor = [System.Drawing.Color]::FromArgb(230,240,255)
    } elseif ($ctrl -is [System.Windows.Forms.CheckBox]) {
      $ctrl.BackColor = [System.Drawing.Color]::FromArgb(220,232,255)
    } else {
      $ctrl.BackColor = [System.Drawing.Color]::FromArgb(220,232,255)
    }
  }
  $script:HighlightedControls = $list.ToArray()
}

function Show-Tutorial {
  param([int]$StepIndex = -1)
  if ($StepIndex -ge 0 -and $StepIndex -lt $script:TutorialSteps.Count) { $script:TutorialIndex = $StepIndex }
  $script:TutorialActive = $true
  Update-TutorialView
  $script:TutorialPanel.Visible = $true
  $script:TutorialPanel.BringToFront()
}

function Hide-Tutorial {
  $script:TutorialActive = $false
  $script:TutorialPanel.Visible = $false
  Clear-TutorialHighlight
}

function Update-TutorialView {
  $step = $script:TutorialSteps[$script:TutorialIndex]
  $script:TutorialTitleLabel.Text = $step.Title
  $script:TutorialBodyLabel.Text = $step.Body
  $script:TutorialCounter.Text = "Step $($script:TutorialIndex + 1) of $($script:TutorialSteps.Count)"
  $script:TutorialBtnPrev.Enabled = $script:TutorialIndex -gt 0
  $script:TutorialBtnNext.Enabled = $script:TutorialIndex -lt ($script:TutorialSteps.Count - 1)
  # Use monospace font for example-output steps so tables align
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

# ── Run Tab: GroupBox — File Paths ──
$grpPaths = New-Object System.Windows.Forms.GroupBox
$grpPaths.Text = 'Session File Paths'; $grpPaths.Location = '6,6'; $grpPaths.Size = '952,115'; $grpPaths.Anchor = 'Top, Left, Right'; $grpPaths.Font = $emphasisFont

$lblStop = New-Object System.Windows.Forms.Label
$lblStop.Location = '10,22'; $lblStop.Size = '100,20'; $lblStop.Text = 'Stop signal path'; $lblStop.Font = $emphasisFont
$txtStop = New-Object System.Windows.Forms.TextBox
$txtStop.Location = '115,19'; $txtStop.Size = '650,24'; $txtStop.Text = (Join-Path $repoRoot 'Mapping\Output\Stop.json'); $txtStop.Anchor = 'Top, Left, Right'; $txtStop.Font = $uiFont; $txtStop.ReadOnly = $true; $txtStop.Cursor = 'Hand'; $txtStop.BackColor = [System.Drawing.Color]::White
$btnBrowseStop = New-Object System.Windows.Forms.Button
$btnBrowseStop.Location = '772,18'; $btnBrowseStop.Size = '30,26'; $btnBrowseStop.Text = [char]0x2026; $btnBrowseStop.Anchor = 'Top, Right'; $btnBrowseStop.FlatStyle = 'Flat'; $btnBrowseStop.Font = $uiFont
$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Location = '810,18'; $btnStop.Size = '130,26'; $btnStop.Text = 'Stop Run  (Ctrl+S)'; $btnStop.Anchor = 'Top, Right'; $btnStop.FlatStyle = 'Flat'; $btnStop.BackColor = [System.Drawing.Color]::FromArgb(255,235,235); $btnStop.Font = $uiFont

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

# ── Run Tab: GroupBox — Run Options ──
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

# ── Run Tab: GroupBox — Launch Configuration ──
$grpLaunch = New-Object System.Windows.Forms.GroupBox
$grpLaunch.Text = 'Launch Configuration'; $grpLaunch.Location = '6,172'; $grpLaunch.Size = '952,200'; $grpLaunch.Anchor = 'Top, Left, Right'; $grpLaunch.Font = $emphasisFont

$lblRunTargets = New-Object System.Windows.Forms.Label
$lblRunTargets.Location = '10,20'; $lblRunTargets.Size = '260,18'; $lblRunTargets.Text = 'Controller targets (one per line)'; $lblRunTargets.Font = $emphasisFont
$txtRunTargets = New-Object System.Windows.Forms.TextBox
$txtRunTargets.Location = '10,40'; $txtRunTargets.Size = '280,100'; $txtRunTargets.Multiline = $true; $txtRunTargets.ScrollBars = 'Vertical'; $txtRunTargets.AcceptsReturn = $true; $txtRunTargets.Font = $uiFont
# ── Worker Options: Structured Controls ──
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
$btnOpenSession.Location = '152,168'; $btnOpenSession.Size = '140,26'; $btnOpenSession.Text = 'Open Session Folder'; $btnOpenSession.FlatStyle = 'Flat'; $btnOpenSession.BackColor = [System.Drawing.Color]::White; $btnOpenSession.Font = $uiFont
$btnCopyStatus = New-Object System.Windows.Forms.Button
$btnCopyStatus.Location = '300,168'; $btnCopyStatus.Size = '110,26'; $btnCopyStatus.Text = 'Copy Status'; $btnCopyStatus.FlatStyle = 'Flat'; $btnCopyStatus.BackColor = [System.Drawing.Color]::White; $btnCopyStatus.Font = $uiFont
$btnCopyHistory = New-Object System.Windows.Forms.Button
$btnCopyHistory.Location = '418,168'; $btnCopyHistory.Size = '110,26'; $btnCopyHistory.Text = 'Copy History'; $btnCopyHistory.FlatStyle = 'Flat'; $btnCopyHistory.BackColor = [System.Drawing.Color]::White; $btnCopyHistory.Font = $uiFont
$btnStartWorker = New-Object System.Windows.Forms.Button
$btnStartWorker.Location = '660,168'; $btnStartWorker.Size = '140,26'; $btnStartWorker.Text = 'Start Local Worker'; $btnStartWorker.Anchor = 'Top, Right'; $btnStartWorker.FlatStyle = 'Flat'; $btnStartWorker.BackColor = [System.Drawing.Color]::FromArgb(225,240,255); $btnStartWorker.Font = $emphasisFont
$btnStartController = New-Object System.Windows.Forms.Button
$btnStartController.Location = '808,168'; $btnStartController.Size = '134,26'; $btnStartController.Text = 'Start Controller'; $btnStartController.Anchor = 'Top, Right'; $btnStartController.FlatStyle = 'Flat'; $btnStartController.BackColor = [System.Drawing.Color]::FromArgb(225,248,236); $btnStartController.Font = $emphasisFont

$grpLaunch.Controls.AddRange(@($lblRunTargets,$txtRunTargets,$lblRunMode,$cmbRunMode,$chkPreflight,$chkRestartSpooler,$lblQueuesAdd,$txtQueuesAdd,$lblQueuesRemove,$txtQueuesRemove,$lblDefaultQueue,$txtDefaultQueue,$lblGeneratedOpts,$txtWorkerOptions,$btnExampleOptions,$btnOpenSession,$btnCopyStatus,$btnCopyHistory,$btnStartWorker,$btnStartController))

# ── Run Tab: Status & History panes ──
$lblStatusPane = New-Object System.Windows.Forms.Label
$lblStatusPane.Location = '8,377'; $lblStatusPane.Size = '120,18'; $lblStatusPane.Text = 'Run Status'; $lblStatusPane.Font = $emphasisFont
$txtStatusView = New-Object System.Windows.Forms.TextBox
$txtStatusView.Location = '6,396'; $txtStatusView.Size = '952,110'; $txtStatusView.Multiline = $true; $txtStatusView.ScrollBars = 'Both'; $txtStatusView.ReadOnly = $true; $txtStatusView.Anchor = 'Top, Left, Right'; $txtStatusView.Font = $monoFont; $txtStatusView.WordWrap = $false; $txtStatusView.BackColor = [System.Drawing.Color]::White; $txtStatusView.Text = 'Launch a run or click Refresh Now to inspect a status snapshot.'
$lblHistoryPane = New-Object System.Windows.Forms.Label
$lblHistoryPane.Location = '8,510'; $lblHistoryPane.Size = '120,18'; $lblHistoryPane.Text = 'Undo / Redo History'; $lblHistoryPane.Font = $emphasisFont
$txtHistoryView = New-Object System.Windows.Forms.TextBox
$txtHistoryView.Location = '6,530'; $txtHistoryView.Size = '952,195'; $txtHistoryView.Multiline = $true; $txtHistoryView.ScrollBars = 'Both'; $txtHistoryView.ReadOnly = $true; $txtHistoryView.Anchor = 'Top, Bottom, Left, Right'; $txtHistoryView.Font = $monoFont; $txtHistoryView.WordWrap = $false; $txtHistoryView.BackColor = [System.Drawing.Color]::White; $txtHistoryView.Text = 'Launch a run or load a history file to inspect undo/redo details.'

$runTab.Controls.AddRange(@($grpPaths,$grpOptions,$grpLaunch,$lblStatusPane,$txtStatusView,$lblHistoryPane,$txtHistoryView))

# ── Kronos Tab: GroupBox — Probe & Inventory ──
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

# ── Kronos Tab: Results pane ──
$lblKronosResults = New-Object System.Windows.Forms.Label
$lblKronosResults.Location = '8,230'; $lblKronosResults.Size = '140,18'; $lblKronosResults.Text = 'Results'; $lblKronosResults.Font = $emphasisFont
$txtClockResults = New-Object System.Windows.Forms.TextBox
$txtClockResults.Location = '6,250'; $txtClockResults.Size = '952,400'; $txtClockResults.Multiline = $true; $txtClockResults.ScrollBars = 'Both'; $txtClockResults.ReadOnly = $true; $txtClockResults.Anchor = 'Top, Bottom, Left, Right'; $txtClockResults.Font = $monoFont; $txtClockResults.WordWrap = $false; $txtClockResults.BackColor = [System.Drawing.Color]::White; $txtClockResults.Text = 'Probe live clocks or search a saved inventory CSV.'

$kronosTab.Controls.AddRange(@($grpKronos,$lblKronosResults,$txtClockResults))

$tabs.TabPages.AddRange(@($runTab,$kronosTab))
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

# ── Tutorial Overlay Panel ──
$script:TutorialPanel = New-Object System.Windows.Forms.Panel
$script:TutorialPanel.Size = New-Object System.Drawing.Size(520,420)
$script:TutorialPanel.BackColor = [System.Drawing.Color]::FromArgb(30,42,56)
$script:TutorialPanel.BorderStyle = 'FixedSingle'
$script:TutorialPanel.Visible = $false
$script:TutorialPanel.Anchor = 'None'

$script:TutorialTitleLabel = New-Object System.Windows.Forms.Label
$script:TutorialTitleLabel.Location = '18,14'
$script:TutorialTitleLabel.Size = '440,28'
$script:TutorialTitleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold',13)
$script:TutorialTitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(230,240,255)
$script:TutorialTitleLabel.Text = ''

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
$script:TutorialBodyLabel.Size = '484,310'
$script:TutorialBodyLabel.Font = New-Object System.Drawing.Font('Segoe UI',9.5)
$script:TutorialBodyLabel.ForeColor = [System.Drawing.Color]::FromArgb(210,220,235)
$script:TutorialBodyLabel.Text = ''

$script:TutorialBtnPrev = New-Object System.Windows.Forms.Button
$script:TutorialBtnPrev.Location = '18,372'
$script:TutorialBtnPrev.Size = '60,32'
$script:TutorialBtnPrev.Text = [char]0x2190 + ' Prev'
$script:TutorialBtnPrev.FlatStyle = 'Flat'
$script:TutorialBtnPrev.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80,100,130)
$script:TutorialBtnPrev.ForeColor = [System.Drawing.Color]::White
$script:TutorialBtnPrev.BackColor = [System.Drawing.Color]::FromArgb(50,65,85)
$script:TutorialBtnPrev.Font = $uiFont
$script:TutorialBtnPrev.Cursor = 'Hand'
$script:TutorialBtnPrev.Add_Click({
  if ($script:TutorialIndex -gt 0) { $script:TutorialIndex--; Update-TutorialView }
})

$script:TutorialCounter = New-Object System.Windows.Forms.Label
$script:TutorialCounter.Location = '180,378'
$script:TutorialCounter.Size = '160,20'
$script:TutorialCounter.TextAlign = 'MiddleCenter'
$script:TutorialCounter.Font = $uiFont
$script:TutorialCounter.ForeColor = [System.Drawing.Color]::FromArgb(160,175,195)

$script:TutorialBtnNext = New-Object System.Windows.Forms.Button
$script:TutorialBtnNext.Location = '440,372'
$script:TutorialBtnNext.Size = '60,32'
$script:TutorialBtnNext.Text = 'Next ' + [char]0x2192
$script:TutorialBtnNext.FlatStyle = 'Flat'
$script:TutorialBtnNext.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80,100,130)
$script:TutorialBtnNext.ForeColor = [System.Drawing.Color]::White
$script:TutorialBtnNext.BackColor = [System.Drawing.Color]::FromArgb(50,65,85)
$script:TutorialBtnNext.Font = $uiFont
$script:TutorialBtnNext.Cursor = 'Hand'
$script:TutorialBtnNext.Add_Click({
  if ($script:TutorialIndex -lt ($script:TutorialSteps.Count - 1)) { $script:TutorialIndex++; Update-TutorialView }
})

$script:TutorialPanel.Controls.AddRange(@(
  $script:TutorialTitleLabel, $btnTutorialClose, $script:TutorialBodyLabel,
  $script:TutorialBtnPrev, $script:TutorialCounter, $script:TutorialBtnNext
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

# ── Tutorial Relaunch Button (on status strip) ──
$btnShowTutorial = New-Object System.Windows.Forms.ToolStripButton
$btnShowTutorial.Text = 'Tutorial (Ctrl+T)'
$btnShowTutorial.DisplayStyle = 'Text'
$btnShowTutorial.Alignment = 'Right'
$btnShowTutorial.Add_Click({ if ($script:TutorialActive) { Hide-Tutorial } else { Show-Tutorial -StepIndex 0 } })
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

# ── Browse button handlers ──
$btnBrowseStop.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select stop-signal file'; if ($p) { $txtStop.Text = $p } })
$btnBrowseStatus.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select status snapshot file'; if ($p) { $txtStatus.Text = $p } })
$btnBrowseHistory.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select undo/redo history file'; if ($p) { $txtUndo.Text = $p } })
$btnBrowseClockOut.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select output CSV path' -Filter 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'; if ($p) { $txtClockOut.Text = $p } })
$btnBrowseInv.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select inventory CSV file' -Filter 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'; if ($p) { $txtInv.Text = $p } })

# ── Click-to-browse on path text fields ──
$txtStop.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select stop-signal file'; if ($p) { $txtStop.Text = $p } })
$txtStatus.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select status snapshot file'; if ($p) { $txtStatus.Text = $p } })
$txtUndo.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select undo/redo history file'; if ($p) { $txtUndo.Text = $p } })
$txtClockOut.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select output CSV path' -Filter 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'; if ($p) { $txtClockOut.Text = $p } })
$txtInv.Add_Click({ $p = Show-BrowseFileDialog -Title 'Select inventory CSV file' -Filter 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'; if ($p) { $txtInv.Text = $p } })

# ── Keyboard shortcuts (KeyDown on the form with KeyPreview) ──
$form.Add_KeyDown({
  param($formSender, $e)
  # Tutorial navigation takes priority when active
  if ($script:TutorialActive) {
    if ($e.KeyCode -eq 'Left')   { $script:TutorialBtnPrev.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true; return }
    if ($e.KeyCode -eq 'Right')  { $script:TutorialBtnNext.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true; return }
    if ($e.KeyCode -eq 'Escape') { Hide-Tutorial; $e.Handled = $true; $e.SuppressKeyPress = $true; return }
  }
  if ($e.Control -and $e.KeyCode -eq 'T') {
    if ($script:TutorialActive) { Hide-Tutorial } else { Show-Tutorial -StepIndex 0 }
    $e.Handled = $true; $e.SuppressKeyPress = $true
  }
  elseif ($e.Control -and $e.KeyCode -eq 'S') { $btnStop.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.KeyCode -eq 'F5') { $btnStatus.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.Control -and $e.KeyCode -eq 'L') { $btnLoad.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.Control -and $e.KeyCode -eq 'Z') { $btnUndo.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.Control -and $e.KeyCode -eq 'Y') { $btnRedo.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
  elseif ($e.Control -and $e.KeyCode -eq 'E') { $btnExampleOptions.PerformClick(); $e.Handled = $true; $e.SuppressKeyPress = $true }
})

# ── Button click handlers (with confirmation dialogs for destructive actions) ──
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
  if (-not $chkAutoRefresh.Checked) { return }
  if ($tabs.SelectedTab -ne $runTab) { return }
  Refresh-RunStatusView
  Refresh-RunHistoryView
})
$nudRefreshSeconds.Add_ValueChanged({
  $refreshTimer.Interval = [int]$nudRefreshSeconds.Value * 1000
  Set-StatusBarText -Category 'Auto refresh' -Message "Auto refresh interval set to $($nudRefreshSeconds.Value) second(s)."
})
$refreshTimer.Start()
$form.Add_FormClosed({ $refreshTimer.Stop() })
Update-RunActionState

# ── Tutorial checkpoint on tab change ──
$tabs.Add_SelectedIndexChanged({
  if ($tabs.SelectedTab -eq $kronosTab) {
    Show-TutorialAtCheckpoint -CheckpointName 'KronosTab' -StepIndex 14
  }
})

[void]$form.ShowDialog()