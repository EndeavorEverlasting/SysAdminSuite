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
  if (-not $txtStatus.Text -or -not (Test-Path -LiteralPath $txtStatus.Text)) { return }
  try { $txtStatusView.Text = Format-ObjectText (Import-RunStatusSnapshot -Path $txtStatus.Text) }
  catch { $txtStatusView.Text = $_.Exception.Message }
}

function Refresh-RunHistoryView {
  if (-not $txtUndo.Text -or -not (Test-Path -LiteralPath $txtUndo.Text)) { return }
  try {
    $script:LoadedSession = Import-UndoRedoSession -Path $txtUndo.Text
    $txtHistoryView.Text = Format-UndoRedoText $script:LoadedSession
  } catch {
    $txtHistoryView.Text = $_.Exception.Message
  }
}

function Start-GuiRun {
  param([ValidateSet('Worker','Controller')][string]$Mode)

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
  $txtHistoryView.Text = 'Waiting for undo/redo history...'
  $txtStatusView.Text = (@(
    "Started $Mode run.",
    "PID: $($proc.Id)",
    "Session root: $($session.Root)",
    "Launcher: $($session.Launcher)",
    ('Worker options: {0}' -f $(if ($workerOptions) { $workerOptions } else { '<none>' }))
  ) -join [Environment]::NewLine)
}

$script:LoadedSession = $null
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SysAdminSuite GUI Harness'
$form.Size = New-Object System.Drawing.Size(1000,790)
$form.StartPosition = 'CenterScreen'

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$runTab = New-Object System.Windows.Forms.TabPage
$runTab.Text = 'Run Control'
$kronosTab = New-Object System.Windows.Forms.TabPage
$kronosTab.Text = 'Kronos Lookup'

$lblStop = New-Object System.Windows.Forms.Label
$lblStop.Location = '12,15'; $lblStop.Size = '100,20'; $lblStop.Text = 'Stop signal path'
$txtStop = New-Object System.Windows.Forms.TextBox
$txtStop.Location = '120,12'; $txtStop.Size = '720,24'; $txtStop.Text = (Join-Path $repoRoot 'Mapping\Output\Stop.json')
$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Location = '850,10'; $btnStop.Size = '100,28'; $btnStop.Text = 'Stop Run'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = '12,50'; $lblStatus.Size = '100,20'; $lblStatus.Text = 'Status path'
$txtStatus = New-Object System.Windows.Forms.TextBox
$txtStatus.Location = '120,47'; $txtStatus.Size = '720,24'; $txtStatus.Text = (Join-Path $repoRoot 'Mapping\Output\status.json')
$btnStatus = New-Object System.Windows.Forms.Button
$btnStatus.Location = '850,45'; $btnStatus.Size = '100,28'; $btnStatus.Text = 'Refresh'

$lblUndo = New-Object System.Windows.Forms.Label
$lblUndo.Location = '12,85'; $lblUndo.Size = '100,20'; $lblUndo.Text = 'History path'
$txtUndo = New-Object System.Windows.Forms.TextBox
$txtUndo.Location = '120,82'; $txtUndo.Size = '720,24'; $txtUndo.Text = (Join-Path $repoRoot 'Mapping\Output\UndoRedo.Controller.json')
$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Location = '850,80'; $btnLoad.Size = '100,28'; $btnLoad.Text = 'Load'

$chkWhatIf = New-Object System.Windows.Forms.CheckBox
$chkWhatIf.Location = '120,114'; $chkWhatIf.Size = '180,24'; $chkWhatIf.Text = 'WhatIf replay (safe)'; $chkWhatIf.Checked = $true
$btnUndo = New-Object System.Windows.Forms.Button
$btnUndo.Location = '680,112'; $btnUndo.Size = '130,28'; $btnUndo.Text = 'Undo Top'
$btnRedo = New-Object System.Windows.Forms.Button
$btnRedo.Location = '820,112'; $btnRedo.Size = '130,28'; $btnRedo.Text = 'Redo Top'

$lblRunTargets = New-Object System.Windows.Forms.Label
$lblRunTargets.Location = '12,150'; $lblRunTargets.Size = '160,20'; $lblRunTargets.Text = 'Controller targets (one/line)'
$txtRunTargets = New-Object System.Windows.Forms.TextBox
$txtRunTargets.Location = '12,175'; $txtRunTargets.Size = '280,120'; $txtRunTargets.Multiline = $true; $txtRunTargets.ScrollBars = 'Vertical'
$lblWorkerOptions = New-Object System.Windows.Forms.Label
$lblWorkerOptions.Location = '310,150'; $lblWorkerOptions.Size = '170,20'; $lblWorkerOptions.Text = 'Worker options passthrough'
$txtWorkerOptions = New-Object System.Windows.Forms.TextBox
$txtWorkerOptions.Location = '310,175'; $txtWorkerOptions.Size = '640,120'; $txtWorkerOptions.Multiline = $true; $txtWorkerOptions.ScrollBars = 'Vertical'; $txtWorkerOptions.Text = "-ListOnly -Preflight"
$lblLaunchHint = New-Object System.Windows.Forms.Label
$lblLaunchHint.Location = '12,302'; $lblLaunchHint.Size = '590,32'; $lblLaunchHint.Text = "Example: -Queues '\\PRINTSRV\Q01','\\PRINTSRV\Q02' -ListOnly -Preflight"
$btnStartWorker = New-Object System.Windows.Forms.Button
$btnStartWorker.Location = '620,300'; $btnStartWorker.Size = '150,30'; $btnStartWorker.Text = 'Start Local Worker'
$btnStartController = New-Object System.Windows.Forms.Button
$btnStartController.Location = '800,300'; $btnStartController.Size = '150,30'; $btnStartController.Text = 'Start Controller'

$txtStatusView = New-Object System.Windows.Forms.TextBox
$txtStatusView.Location = '12,340'; $txtStatusView.Size = '938,150'; $txtStatusView.Multiline = $true; $txtStatusView.ScrollBars = 'Vertical'; $txtStatusView.ReadOnly = $true
$txtHistoryView = New-Object System.Windows.Forms.TextBox
$txtHistoryView.Location = '12,505'; $txtHistoryView.Size = '938,220'; $txtHistoryView.Multiline = $true; $txtHistoryView.ScrollBars = 'Vertical'; $txtHistoryView.ReadOnly = $true

$runTab.Controls.AddRange(@(
  $lblStop,$txtStop,$btnStop,$lblStatus,$txtStatus,$btnStatus,$lblUndo,$txtUndo,$btnLoad,$chkWhatIf,$btnUndo,$btnRedo,
  $lblRunTargets,$txtRunTargets,$lblWorkerOptions,$txtWorkerOptions,$lblLaunchHint,$btnStartWorker,$btnStartController,
  $txtStatusView,$txtHistoryView
))

$lblTargets = New-Object System.Windows.Forms.Label
$lblTargets.Location = '12,15'; $lblTargets.Size = '120,20'; $lblTargets.Text = 'Targets (one/line)'
$txtTargets = New-Object System.Windows.Forms.TextBox
$txtTargets.Location = '12,40'; $txtTargets.Size = '300,210'; $txtTargets.Multiline = $true; $txtTargets.ScrollBars = 'Vertical'
$lblClockOut = New-Object System.Windows.Forms.Label
$lblClockOut.Location = '330,15'; $lblClockOut.Size = '90,20'; $lblClockOut.Text = 'Output CSV'
$txtClockOut = New-Object System.Windows.Forms.TextBox
$txtClockOut.Location = '330,40'; $txtClockOut.Size = '620,24'; $txtClockOut.Text = (Join-Path $repoRoot 'GetInfo\KronosClockInventory.csv')
$lblInv = New-Object System.Windows.Forms.Label
$lblInv.Location = '330,75'; $lblInv.Size = '100,20'; $lblInv.Text = 'Inventory CSV'
$txtInv = New-Object System.Windows.Forms.TextBox
$txtInv.Location = '330,100'; $txtInv.Size = '620,24'; $txtInv.Text = $txtClockOut.Text
$cmbLookup = New-Object System.Windows.Forms.ComboBox
$cmbLookup.Location = '330,135'; $cmbLookup.Size = '160,24'; $cmbLookup.DropDownStyle = 'DropDownList'
@('Any','IP','MAC','Serial','HostName','DeviceName') | ForEach-Object { [void]$cmbLookup.Items.Add($_) }
$cmbLookup.SelectedIndex = 0
$txtLookup = New-Object System.Windows.Forms.TextBox
$txtLookup.Location = '505,135'; $txtLookup.Size = '290,24'
$btnProbe = New-Object System.Windows.Forms.Button
$btnProbe.Location = '810,134'; $btnProbe.Size = '140,28'; $btnProbe.Text = 'Probe Targets'
$btnInventory = New-Object System.Windows.Forms.Button
$btnInventory.Location = '330,170'; $btnInventory.Size = '160,28'; $btnInventory.Text = 'Load Inventory'
$btnFind = New-Object System.Windows.Forms.Button
$btnFind.Location = '505,170'; $btnFind.Size = '140,28'; $btnFind.Text = 'Find Match'
$txtClockResults = New-Object System.Windows.Forms.TextBox
$txtClockResults.Location = '12,270'; $txtClockResults.Size = '938,380'; $txtClockResults.Multiline = $true; $txtClockResults.ScrollBars = 'Vertical'; $txtClockResults.ReadOnly = $true

$kronosTab.Controls.AddRange(@($lblTargets,$txtTargets,$lblClockOut,$txtClockOut,$lblInv,$txtInv,$cmbLookup,$txtLookup,$btnProbe,$btnInventory,$btnFind,$txtClockResults))

$tabs.TabPages.AddRange(@($runTab,$kronosTab))
$form.Controls.Add($tabs)

$btnStop.Add_Click({
  try {
    $signal = Request-RunStop -Path $txtStop.Text -Reason 'GUI stop button pressed'
    [System.Windows.Forms.MessageBox]::Show((Format-ObjectText $signal),'Stop requested') | Out-Null
  } catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Stop failed') | Out-Null
  }
})

$btnStatus.Add_Click({ Refresh-RunStatusView })
$btnLoad.Add_Click({ Refresh-RunHistoryView })

$btnUndo.Add_Click({
  try {
    if (-not $script:LoadedSession) { throw 'Load an undo/redo session first.' }
    $result = Replay-UndoRedoAction -Session $script:LoadedSession -Operation Undo -WhatIf:$chkWhatIf.Checked
    $txtHistoryView.Text = (Format-UndoRedoText $script:LoadedSession) + [Environment]::NewLine + [Environment]::NewLine + (Format-ObjectText $result)
  } catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Undo failed') | Out-Null
  }
})

$btnRedo.Add_Click({
  try {
    if (-not $script:LoadedSession) { throw 'Load an undo/redo session first.' }
    $result = Replay-UndoRedoAction -Session $script:LoadedSession -Operation Redo -WhatIf:$chkWhatIf.Checked
    $txtHistoryView.Text = (Format-UndoRedoText $script:LoadedSession) + [Environment]::NewLine + [Environment]::NewLine + (Format-ObjectText $result)
  } catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Redo failed') | Out-Null
  }
})

$btnStartWorker.Add_Click({
  try { Start-GuiRun -Mode Worker }
  catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Local worker start failed') | Out-Null }
})

$btnStartController.Add_Click({
  try { Start-GuiRun -Mode Controller }
  catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Controller start failed') | Out-Null }
})

$btnProbe.Add_Click({
  try {
    $targets = @($txtTargets.Lines | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
    if (-not $targets.Count) { throw 'Enter at least one IP or hostname.' }
    $results = & $kronosScript -Targets $targets -OutCsv $txtClockOut.Text
    $txtInv.Text = $txtClockOut.Text
    $txtClockResults.Text = Format-ObjectText @($results)
  } catch {
    $txtClockResults.Text = $_.Exception.Message
  }
})

$btnInventory.Add_Click({
  try { $txtClockResults.Text = Format-ObjectText @(& $kronosScript -InventoryPath $txtInv.Text) }
  catch { $txtClockResults.Text = $_.Exception.Message }
})

$btnFind.Add_Click({
  try {
    $terms = @($txtLookup.Text -split '[,;\r\n]+' | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
    if (-not $terms.Count) { throw 'Enter a lookup value.' }
    $txtClockResults.Text = Format-ObjectText @(& $kronosScript -InventoryPath $txtInv.Text -LookupBy $cmbLookup.SelectedItem -LookupValue $terms)
  } catch {
    $txtClockResults.Text = $_.Exception.Message
  }
})

$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = 3000
$refreshTimer.Add_Tick({
  if ($tabs.SelectedTab -ne $runTab) { return }
  Refresh-RunStatusView
  Refresh-RunHistoryView
})
$refreshTimer.Start()
$form.Add_FormClosed({ $refreshTimer.Stop() })

[void]$form.ShowDialog()