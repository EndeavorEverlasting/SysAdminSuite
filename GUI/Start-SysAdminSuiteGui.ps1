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

$guiRoot = $PSScriptRoot
$corePath = Join-Path $guiRoot 'Start-SysAdminSuiteGui.Core.ps1'
$generatedPath = Join-Path $guiRoot 'Start-SysAdminSuiteGui.Integrated.generated.ps1'

if (-not (Test-Path -LiteralPath $corePath)) {
  throw "Core GUI script not found: $corePath"
}

$fieldHotfixTabInjection = @'
# -- Field Hotfixes Tab --
$fieldHotfixesTab = New-Object System.Windows.Forms.TabPage
$fieldHotfixesTab.Text = 'Field Hotfixes'
$fieldHotfixesTab.BackColor = [System.Drawing.Color]::WhiteSmoke

$fieldHotfixManifestPath = Join-Path $repoRoot 'configs\hotfix-commands\cybernet-setup-completion-flag.json'
$fieldHotfixGuiPath = Join-Path $repoRoot 'GUI\Start-FieldHotfixesGui.ps1'
$fieldHotfixManifest = $null
try {
  if (Test-Path -LiteralPath $fieldHotfixManifestPath) {
    $fieldHotfixManifest = Get-Content -LiteralPath $fieldHotfixManifestPath -Raw | ConvertFrom-Json
  }
} catch {
  $fieldHotfixManifest = $null
}

$lblFieldHotfixTitle = New-Object System.Windows.Forms.Label
$lblFieldHotfixTitle.Location = '18,16'
$lblFieldHotfixTitle.Size = '910,28'
$lblFieldHotfixTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold',14)
$lblFieldHotfixTitle.Text = if ($fieldHotfixManifest) { $fieldHotfixManifest.title } else { 'Field Hotfixes' }

$lblFieldHotfixStatus = New-Object System.Windows.Forms.Label
$lblFieldHotfixStatus.Location = '20,50'
$lblFieldHotfixStatus.Size = '910,24'
$lblFieldHotfixStatus.Font = $uiFont
$lblFieldHotfixStatus.Text = if ($fieldHotfixManifest) { "Status: $($fieldHotfixManifest.status)    Version: $($fieldHotfixManifest.version)    Risk: $($fieldHotfixManifest.risk_level)    Operator: standing at target" } else { "Manifest missing: $fieldHotfixManifestPath" }

$lblFieldHotfixMode = New-Object System.Windows.Forms.Label
$lblFieldHotfixMode.Location = '20,86'
$lblFieldHotfixMode.Size = '120,22'
$lblFieldHotfixMode.Text = 'QR payload mode'
$lblFieldHotfixMode.Font = $emphasisFont

$cmbFieldHotfixPayload = New-Object System.Windows.Forms.ComboBox
$cmbFieldHotfixPayload.Location = '145,82'
$cmbFieldHotfixPayload.Size = '250,26'
$cmbFieldHotfixPayload.DropDownStyle = 'DropDownList'
[void]$cmbFieldHotfixPayload.Items.Add('CMD Shift+F10 payload')
[void]$cmbFieldHotfixPayload.Items.Add('PowerShell console payload')
$cmbFieldHotfixPayload.SelectedIndex = 0

$btnFieldHotfixRefresh = New-Object System.Windows.Forms.Button
$btnFieldHotfixRefresh.Location = '410,80'
$btnFieldHotfixRefresh.Size = '110,30'
$btnFieldHotfixRefresh.Text = 'Refresh QR'
$btnFieldHotfixRefresh.FlatStyle = 'Flat'
$btnFieldHotfixRefresh.BackColor = [System.Drawing.Color]::White

$btnFieldHotfixCopy = New-Object System.Windows.Forms.Button
$btnFieldHotfixCopy.Location = '530,80'
$btnFieldHotfixCopy.Size = '120,30'
$btnFieldHotfixCopy.Text = 'Copy command'
$btnFieldHotfixCopy.FlatStyle = 'Flat'
$btnFieldHotfixCopy.BackColor = [System.Drawing.Color]::White

$btnFieldHotfixOpen = New-Object System.Windows.Forms.Button
$btnFieldHotfixOpen.Location = '660,80'
$btnFieldHotfixOpen.Size = '260,30'
$btnFieldHotfixOpen.Text = 'Open large Field Hotfixes QR window'
$btnFieldHotfixOpen.FlatStyle = 'Flat'
$btnFieldHotfixOpen.BackColor = [System.Drawing.Color]::FromArgb(227,248,227)

$txtFieldHotfixCommand = New-Object System.Windows.Forms.TextBox
$txtFieldHotfixCommand.Location = '20,120'
$txtFieldHotfixCommand.Size = '625,76'
$txtFieldHotfixCommand.Multiline = $true
$txtFieldHotfixCommand.ReadOnly = $true
$txtFieldHotfixCommand.ScrollBars = 'Vertical'
$txtFieldHotfixCommand.Font = New-Object System.Drawing.Font('Consolas',10)
$txtFieldHotfixCommand.BackColor = [System.Drawing.Color]::White

$txtFieldHotfixInstructions = New-Object System.Windows.Forms.TextBox
$txtFieldHotfixInstructions.Location = '20,214'
$txtFieldHotfixInstructions.Size = '625,430'
$txtFieldHotfixInstructions.Multiline = $true
$txtFieldHotfixInstructions.ReadOnly = $true
$txtFieldHotfixInstructions.ScrollBars = 'Vertical'
$txtFieldHotfixInstructions.Font = New-Object System.Drawing.Font('Segoe UI',10)
$txtFieldHotfixInstructions.BackColor = [System.Drawing.Color]::White

$fieldHotfixInstructionText = @(
  'Scanner workflow',
  '1. Stand at the Cybernet showing the Windows setup error.',
  '2. Press Shift+F10 to open Command Prompt.',
  '3. Scan the CMD QR payload into the Command Prompt window.',
  '4. Press Enter if the scanner does not send Enter automatically.',
  '5. Let the device restart and continue post-install.',
  '',
  'Use this only before final post-install identity/app binding.'
)
if ($fieldHotfixManifest) {
  $fieldHotfixInstructionText += @('', 'Preconditions')
  $fieldHotfixInstructionText += @($fieldHotfixManifest.preconditions | ForEach-Object { "- $_" })
  $fieldHotfixInstructionText += @('', 'Forbidden use')
  $fieldHotfixInstructionText += @($fieldHotfixManifest.forbidden_use | ForEach-Object { "- $_" })
  $fieldHotfixInstructionText += @('', 'Expected result', $fieldHotfixManifest.expected_result)
}
$txtFieldHotfixInstructions.Text = $fieldHotfixInstructionText -join "`r`n"

$picFieldHotfixQr = New-Object System.Windows.Forms.PictureBox
$picFieldHotfixQr.Location = '680,130'
$picFieldHotfixQr.Size = '240,240'
$picFieldHotfixQr.SizeMode = 'Zoom'
$picFieldHotfixQr.BorderStyle = 'FixedSingle'
$picFieldHotfixQr.BackColor = [System.Drawing.Color]::White

$lblFieldHotfixQrHint = New-Object System.Windows.Forms.Label
$lblFieldHotfixQrHint.Location = '660,386'
$lblFieldHotfixQrHint.Size = '285,70'
$lblFieldHotfixQrHint.TextAlign = 'MiddleCenter'
$lblFieldHotfixQrHint.Font = $uiFont
$lblFieldHotfixQrHint.Text = if ($script:QRCoderAvailable) { 'Scan this QR into Shift+F10 Command Prompt on the target Cybernet.' } else { 'QRCoder.dll is unavailable. Use Copy command or the dedicated window on an admin box with QRCoder installed.' }

$lblFieldHotfixManifest = New-Object System.Windows.Forms.Label
$lblFieldHotfixManifest.Location = '20,654'
$lblFieldHotfixManifest.Size = '920,22'
$lblFieldHotfixManifest.ForeColor = [System.Drawing.Color]::FromArgb(80,80,80)
$lblFieldHotfixManifest.Text = "Manifest: $fieldHotfixManifestPath"

$updateFieldHotfixQr = {
  if ($fieldHotfixManifest) {
    $payload = if ($cmbFieldHotfixPayload.SelectedIndex -eq 1) { [string]$fieldHotfixManifest.qr_payloads.powershell_console } else { [string]$fieldHotfixManifest.qr_payloads.cmd_shift_f10 }
  } else {
    $payload = 'Hotfix manifest unavailable.'
  }
  $txtFieldHotfixCommand.Text = $payload
  Set-QRCodeImage -PictureBox $picFieldHotfixQr -Text $payload -PixelsPerModule 7
}

$cmbFieldHotfixPayload.Add_SelectedIndexChanged($updateFieldHotfixQr)
$btnFieldHotfixRefresh.Add_Click($updateFieldHotfixQr)
$btnFieldHotfixCopy.Add_Click({
  try { Copy-TextToClipboard -Value $txtFieldHotfixCommand.Text -Label 'Field hotfix command' }
  catch { Set-StatusBarText -Category 'Error' -Message 'Unable to copy the field hotfix command.' }
})
$btnFieldHotfixOpen.Add_Click({
  try {
    if (-not (Test-Path -LiteralPath $fieldHotfixGuiPath)) { throw "Field Hotfixes GUI not found: $fieldHotfixGuiPath" }
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',"`"$fieldHotfixGuiPath`"") | Out-Null
    Set-StatusBarText -Category 'Opened' -Message 'Opened the large Field Hotfixes QR window.'
  } catch {
    Set-StatusBarText -Category 'Error' -Message $_.Exception.Message
  }
})

$fieldHotfixesTab.Controls.AddRange(@(
  $lblFieldHotfixTitle,$lblFieldHotfixStatus,$lblFieldHotfixMode,$cmbFieldHotfixPayload,
  $btnFieldHotfixRefresh,$btnFieldHotfixCopy,$btnFieldHotfixOpen,$txtFieldHotfixCommand,
  $txtFieldHotfixInstructions,$picFieldHotfixQr,$lblFieldHotfixQrHint,$lblFieldHotfixManifest
))
& $updateFieldHotfixQr
'@

$tabAnchor = '$tabs.TabPages.AddRange(@($runTab,$kronosTab,$compareTab,$deployTrackTab,$machineInfoTab,$bomTab))'
$tabReplacement = $fieldHotfixTabInjection + [Environment]::NewLine + '$tabs.TabPages.AddRange(@($runTab,$kronosTab,$compareTab,$deployTrackTab,$machineInfoTab,$bomTab,$fieldHotfixesTab))'

$coreSource = Get-Content -LiteralPath $corePath -Raw
if (-not $coreSource.Contains($tabAnchor)) {
  throw 'Unable to find SysAdminSuite tab collection anchor for Field Hotfixes integration.'
}

$integratedSource = $coreSource.Replace($tabAnchor, $tabReplacement)
$utf8WithBom = New-Object System.Text.UTF8Encoding($true)
try {
  [System.IO.File]::WriteAllText($generatedPath, $integratedSource, $utf8WithBom)
  & $generatedPath
} finally {
  Remove-Item -LiteralPath $generatedPath -Force -ErrorAction SilentlyContinue
}
