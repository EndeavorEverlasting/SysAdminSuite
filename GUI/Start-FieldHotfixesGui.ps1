[CmdletBinding()]
param(
  [string]$ManifestPath,
  [switch]$ShowPowerShellPayload
)

$runningOnWindows = if ($PSVersionTable.PSVersion.Major -ge 6) { $IsWindows } else { $env:OS -eq 'Windows_NT' }
if (-not $runningOnWindows) { throw 'The Field Hotfixes GUI is supported on Windows only.' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
  if ($PSCommandPath) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") | Out-Null
    return
  }
  throw 'Relaunch this GUI in STA mode.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
  $ManifestPath = Join-Path $repoRoot 'configs\hotfix-commands\cybernet-setup-completion-flag.json'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:QRCoderAvailable = $false
$qrCoderDll = Join-Path $repoRoot 'lib\QRCoder.dll'
if (Test-Path -LiteralPath $qrCoderDll) {
  try { Add-Type -Path $qrCoderDll -ErrorAction Stop; $script:QRCoderAvailable = $true }
  catch { Write-Warning "QRCoder DLL failed to load: $_" }
}

function New-HotfixQrBitmap {
  param([Parameter(Mandatory)][string]$Text, [int]$PixelsPerModule = 8)
  if (-not $script:QRCoderAvailable) { return $null }
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  $qrGen = $null
  $qrData = $null
  $qrCode = $null
  try {
    $qrGen = New-Object QRCoder.QRCodeGenerator
    $qrData = $qrGen.CreateQrCode($Text.Trim(), [QRCoder.QRCodeGenerator+ECCLevel]::Q)
    $qrCode = New-Object QRCoder.QRCode($qrData)
    return $qrCode.GetGraphic($PixelsPerModule)
  } catch {
    return $null
  } finally {
    if ($qrCode) { $qrCode.Dispose() }
    if ($qrGen) { $qrGen.Dispose() }
  }
}

function Import-HotfixCommandManifest {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Hotfix manifest not found: $Path" }
  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-HotfixPayloadText {
  param([Parameter(Mandatory)]$Manifest, [bool]$PowerShellPayload)
  if ($PowerShellPayload) { return [string]$Manifest.qr_payloads.powershell_console }
  return [string]$Manifest.qr_payloads.cmd_shift_f10
}

function Set-HotfixQrImage {
  param(
    [Parameter(Mandatory)][System.Windows.Forms.PictureBox]$PictureBox,
    [Parameter(Mandatory)][string]$Text
  )
  if ($PictureBox.Image) { $PictureBox.Image.Dispose(); $PictureBox.Image = $null }
  $bmp = New-HotfixQrBitmap -Text $Text -PixelsPerModule 7
  if ($bmp) {
    $PictureBox.Image = $bmp
    $PictureBox.Visible = $true
  } else {
    $PictureBox.Visible = $false
  }
}

$manifest = Import-HotfixCommandManifest -Path $ManifestPath

$form = New-Object System.Windows.Forms.Form
$form.Text = 'SysAdminSuite - Field Hotfixes'
$form.Size = New-Object System.Drawing.Size(980,760)
$form.MinimumSize = New-Object System.Drawing.Size(900,700)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)
$form.Font = New-Object System.Drawing.Font('Segoe UI',9)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$fieldHotfixesTab = New-Object System.Windows.Forms.TabPage
$fieldHotfixesTab.Text = 'Field Hotfixes'
$fieldHotfixesTab.BackColor = [System.Drawing.Color]::WhiteSmoke
$tabs.Controls.Add($fieldHotfixesTab)
$form.Controls.Add($tabs)

$title = New-Object System.Windows.Forms.Label
$title.Location = '16,14'
$title.Size = '900,28'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold',14)
$title.Text = $manifest.title

$status = New-Object System.Windows.Forms.Label
$status.Location = '18,48'
$status.Size = '900,22'
$status.Text = "Status: $($manifest.status)    Version: $($manifest.version)    Risk: $($manifest.risk_level)    Operator: standing at target"

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Location = '18,82'
$modeLabel.Size = '120,22'
$modeLabel.Text = 'QR payload mode'

$payloadMode = New-Object System.Windows.Forms.ComboBox
$payloadMode.Location = '145,78'
$payloadMode.Size = '240,26'
$payloadMode.DropDownStyle = 'DropDownList'
[void]$payloadMode.Items.Add('CMD Shift+F10 payload')
[void]$payloadMode.Items.Add('PowerShell console payload')
$payloadMode.SelectedIndex = if ($ShowPowerShellPayload) { 1 } else { 0 }

$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Location = '400,76'
$copyButton.Size = '135,30'
$copyButton.Text = 'Copy command'
$copyButton.FlatStyle = 'Flat'

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Location = '545,76'
$refreshButton.Size = '115,30'
$refreshButton.Text = 'Refresh QR'
$refreshButton.FlatStyle = 'Flat'

$commandText = New-Object System.Windows.Forms.TextBox
$commandText.Location = '18,118'
$commandText.Size = '625,72'
$commandText.Multiline = $true
$commandText.ReadOnly = $true
$commandText.ScrollBars = 'Vertical'
$commandText.Font = New-Object System.Drawing.Font('Consolas',10)
$commandText.BackColor = [System.Drawing.Color]::White

$qrBox = New-Object System.Windows.Forms.PictureBox
$qrBox.Location = '670,78'
$qrBox.Size = '270,270'
$qrBox.SizeMode = 'Zoom'
$qrBox.BorderStyle = 'FixedSingle'
$qrBox.BackColor = [System.Drawing.Color]::White

$noQrLabel = New-Object System.Windows.Forms.Label
$noQrLabel.Location = '670,358'
$noQrLabel.Size = '270,42'
$noQrLabel.TextAlign = 'MiddleCenter'
$noQrLabel.ForeColor = [System.Drawing.Color]::FromArgb(120,40,40)
$noQrLabel.Text = if ($script:QRCoderAvailable) { '' } else { 'QRCoder.dll not available. Use Copy command or install lib\QRCoder.dll.' }

$instructions = New-Object System.Windows.Forms.TextBox
$instructions.Location = '18,210'
$instructions.Size = '625,420'
$instructions.Multiline = $true
$instructions.ReadOnly = $true
$instructions.ScrollBars = 'Vertical'
$instructions.BackColor = [System.Drawing.Color]::White
$instructions.Font = New-Object System.Drawing.Font('Segoe UI',10)
$instructions.Text = @(
  'Use case',
  ($manifest.applies_to -join "`r`n"),
  '',
  'Preconditions',
  (($manifest.preconditions | ForEach-Object { "- $_" }) -join "`r`n"),
  '',
  'Scan path',
  (($manifest.scan_instructions | ForEach-Object { "- $_" }) -join "`r`n"),
  '',
  'Forbidden use',
  (($manifest.forbidden_use | ForEach-Object { "- $_" }) -join "`r`n"),
  '',
  'Expected result',
  $manifest.expected_result,
  '',
  'Evidence to capture',
  (($manifest.evidence_to_capture | ForEach-Object { "- $_" }) -join "`r`n")
) -join "`r`n"

$resultLabel = New-Object System.Windows.Forms.Label
$resultLabel.Location = '670,412'
$resultLabel.Size = '270,130'
$resultLabel.Text = "Scanner workflow:`r`n1. Stand at the Cybernet.`r`n2. Press Shift+F10 at the Windows setup error screen.`r`n3. Scan the CMD QR into Command Prompt.`r`n4. Press Enter if needed.`r`n5. Let the device restart."

$manifestPathLabel = New-Object System.Windows.Forms.Label
$manifestPathLabel.Location = '18,645'
$manifestPathLabel.Size = '920,24'
$manifestPathLabel.ForeColor = [System.Drawing.Color]::FromArgb(80,80,80)
$manifestPathLabel.Text = "Manifest: $ManifestPath"

$updatePayload = {
  $usePs = $payloadMode.SelectedIndex -eq 1
  $payload = Get-HotfixPayloadText -Manifest $manifest -PowerShellPayload $usePs
  $commandText.Text = $payload
  Set-HotfixQrImage -PictureBox $qrBox -Text $payload
  if ($script:QRCoderAvailable) { $noQrLabel.Text = '' }
}

$payloadMode.Add_SelectedIndexChanged($updatePayload)
$refreshButton.Add_Click($updatePayload)
$copyButton.Add_Click({
  if (-not [string]::IsNullOrWhiteSpace($commandText.Text)) {
    [System.Windows.Forms.Clipboard]::SetText($commandText.Text)
  }
})

$fieldHotfixesTab.Controls.AddRange(@(
  $title, $status, $modeLabel, $payloadMode, $copyButton, $refreshButton,
  $commandText, $instructions, $qrBox, $noQrLabel, $resultLabel, $manifestPathLabel
))

& $updatePayload
[void]$form.ShowDialog()
