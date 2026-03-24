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

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Format-ObjectText {
  param([object]$InputObject)
  if ($null -eq $InputObject) { return 'No data loaded.' }
  if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
    return (($InputObject | Select-Object QueryInput,IPAddress,HostName,DeviceName,MACAddress,SerialNumber,Model,Reachable | Format-Table -AutoSize | Out-String).Trim())
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

$script:LoadedSession = $null
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SysAdminSuite GUI Harness'
$form.Size = New-Object System.Drawing.Size(980,720)
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

$txtStatusView = New-Object System.Windows.Forms.TextBox
$txtStatusView.Location = '12,150'; $txtStatusView.Size = '938,200'; $txtStatusView.Multiline = $true; $txtStatusView.ScrollBars = 'Vertical'; $txtStatusView.ReadOnly = $true
$txtHistoryView = New-Object System.Windows.Forms.TextBox
$txtHistoryView.Location = '12,370'; $txtHistoryView.Size = '938,280'; $txtHistoryView.Multiline = $true; $txtHistoryView.ScrollBars = 'Vertical'; $txtHistoryView.ReadOnly = $true

$runTab.Controls.AddRange(@($lblStop,$txtStop,$btnStop,$lblStatus,$txtStatus,$btnStatus,$lblUndo,$txtUndo,$btnLoad,$chkWhatIf,$btnUndo,$btnRedo,$txtStatusView,$txtHistoryView))

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

$btnStatus.Add_Click({
  try { $txtStatusView.Text = Format-ObjectText (Import-RunStatusSnapshot -Path $txtStatus.Text) }
  catch { $txtStatusView.Text = $_.Exception.Message }
})

$btnLoad.Add_Click({
  try {
    $script:LoadedSession = Import-UndoRedoSession -Path $txtUndo.Text
    $txtHistoryView.Text = Format-UndoRedoText $script:LoadedSession
  } catch {
    $txtHistoryView.Text = $_.Exception.Message
  }
})

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

[void]$form.ShowDialog()