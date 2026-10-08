<#
  SysAdminSuite local TCP/IP printer mapping GUI.
  A native Windows front door; no operator PowerShell commands are required.
  Store profile hints locally. Never cache a prior panel-IP confirmation.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
  throw 'Start via Map-AgilantHqPrinter.cmd (STA desktop launcher).'
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$repoRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $repoRoot 'mapping\Invoke-LocalTcpPrinter.ps1'
if (-not (Test-Path -LiteralPath $engine)) { throw 'Local printer mapper engine is missing.' }
$profilesDir = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\PrinterMapping\profiles'
[void](New-Item -ItemType Directory -Path $profilesDir -Force)
$script:plannedFingerprint = ''
$script:lastState = ''

function New-Lbl([string]$Text, [int]$X, [int]$Y, [int]$Width = 720) {
  $c = New-Object System.Windows.Forms.Label
  $c.Text = $Text; $c.Location = New-Object System.Drawing.Point($X, $Y)
  $c.Size = New-Object System.Drawing.Size($Width, 24)
  return $c
}
function New-Txt([int]$Y, [string]$Value = '') {
  $c = New-Object System.Windows.Forms.TextBox
  $c.Text = $Value; $c.Location = New-Object System.Drawing.Point(18, $Y)
  $c.Size = New-Object System.Drawing.Size(730, 28)
  return $c
}
function New-Btn([string]$Text,[int]$X,[int]$Y,[int]$Width) {
  $c = New-Object System.Windows.Forms.Button
  $c.Text = $Text; $c.Location = New-Object System.Drawing.Point($X, $Y)
  $c.Size = New-Object System.Drawing.Size($Width, 34)
  return $c
}
function PSQuote([string]$Value) {
  return "'" + $Value.Replace("'","''") + "'"
}
function Get-ProfilePath([string]$Name) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($Name.Trim().ToLowerInvariant())
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() }
  finally { $sha.Dispose() }
  return Join-Path $profilesDir ($hash + '.json')
}
function Fingerprint {
  return (@($txtName.Text, $txtHost.Text, $txtPanel.Text, [string]$cmbDriver.SelectedItem, [string]$chkOverride.Checked, [string]$chkAdopt.Checked, $txtSsid.Text) -join [char]31)
}
function Reset-Plan {
  $script:plannedFingerprint = ''
  $btnMap.Enabled = $false; $btnTest.Enabled = $false
}
function Invoke-Engine([string]$Mode, [bool]$Confirmed) {
  $arguments = @(
    '-Mode', (PSQuote $Mode), '-PrinterName', (PSQuote $txtName.Text.Trim()),
    '-HostOrAddress', (PSQuote $txtHost.Text.Trim()),
    '-PanelAddress', (PSQuote $txtPanel.Text.Trim()),
    '-DriverName', (PSQuote ([string]$cmbDriver.SelectedItem)),
    '-ExpectedSsid', (PSQuote $txtSsid.Text.Trim())
  )
  if ($Confirmed) { $arguments += '-PanelConfirmed' }
  if ($chkSite.Checked) { $arguments += '-SiteConfirmed' }
  if ($chkAdopt.Checked) { $arguments += '-AdoptExistingQueue' }
  if ($chkOverride.Checked) { $arguments += '-UsePanelAddress' }
  $scriptText = '& ' + (PSQuote $engine) + ' ' + ($arguments -join ' ')
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptText))
  $stdout = Join-Path $env:TEMP ('sas-printer-out-' + [guid]::NewGuid().ToString('N') + '.txt')
  $stderr = Join-Path $env:TEMP ('sas-printer-err-' + [guid]::NewGuid().ToString('N') + '.txt')
  try {
    $process = Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @(
      '-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded
    ) -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $raw = [IO.File]::ReadAllText($stdout)
    if ($process.ExitCode -ne 0 -and -not $raw.Trim()) {
      throw ('Workflow could not run: ' + [IO.File]::ReadAllText($stderr))
    }
    $outcome = $raw | ConvertFrom-Json
    if (-not $outcome -or -not $outcome.State) { throw 'Workflow returned no valid outcome receipt.' }
    $txtResult.Text = $raw
    $lblState.Text = 'Outcome: ' + $outcome.State
    return $outcome
  } finally {
    Remove-Item -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue
  }
}
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SysAdminSuite | Agilant HQ Printer Mapping'
$form.Size = New-Object System.Drawing.Size(790, 910)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(790, 910)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$form.Controls.Add((New-Lbl 'Agilant HQ local TCP/IP mapping - NOT the Northwell shared-printer workflow' 18 12))
$form.Controls.Add((New-Lbl 'Saved profile (last address is only a hint; never accepted as fresh panel proof)' 18 44))
$cmbProfiles = New-Object System.Windows.Forms.ComboBox
$cmbProfiles.Location = New-Object System.Drawing.Point(18, 70)
$cmbProfiles.Size = New-Object System.Drawing.Size(540, 28)
$cmbProfiles.DropDownStyle = 'DropDownList'
$form.Controls.Add($cmbProfiles)
$btnSave = New-Btn 'Save / Update profile' 570 68 178
$form.Controls.Add($btnSave)

$form.Controls.Add((New-Lbl 'Windows printer display name' 18 106))
$txtName = New-Txt 132
$form.Controls.Add($txtName)
$form.Controls.Add((New-Lbl 'Printer hostname (preferred) or IPv4 address' 18 171))
$txtHost = New-Txt 197
$form.Controls.Add($txtHost)
$form.Controls.Add((New-Lbl 'CURRENT IPv4 shown on the physical printer panel (never reuse stale IP)' 18 236))
$txtPanel = New-Txt 262
$form.Controls.Add($txtPanel)
$form.Controls.Add((New-Lbl 'Installed printer driver (select an exact match)' 18 302))
$cmbDriver = New-Object System.Windows.Forms.ComboBox
$cmbDriver.Location = New-Object System.Drawing.Point(18, 330)
$cmbDriver.Size = New-Object System.Drawing.Size(730, 29)
$cmbDriver.DropDownStyle = 'DropDownList'
$form.Controls.Add($cmbDriver)
try {
  @(Get-PrinterDriver | Sort-Object Name | Select-Object -ExpandProperty Name) |
    ForEach-Object { [void]$cmbDriver.Items.Add($_) }
  if ($cmbDriver.Items.Contains('HP Universal Printing PCL 6 (v6.7.0)')) {
    $cmbDriver.SelectedItem = 'HP Universal Printing PCL 6 (v6.7.0)'
  }
} catch {}

$chkOverride = New-Object System.Windows.Forms.CheckBox
$chkOverride.Text = 'Use the panel IP when hostname DNS is missing or differs (explicit recovery)'
$chkOverride.Location = New-Object System.Drawing.Point(18, 378)
$chkOverride.Size = New-Object System.Drawing.Size(730, 26)
$form.Controls.Add($chkOverride)
$chkPanel = New-Object System.Windows.Forms.CheckBox
$chkPanel.Text = 'I have just read this current IP from the actual printer display'
$chkPanel.Location = New-Object System.Drawing.Point(18, 410)
$chkPanel.Size = New-Object System.Drawing.Size(730, 26)
$form.Controls.Add($chkPanel)
$chkAdopt = New-Object System.Windows.Forms.CheckBox
$chkAdopt.Text = 'Adopt a pre-existing, matching TCP/9100 printer queue if preview identifies it'
$chkAdopt.Location = New-Object System.Drawing.Point(18, 444)
$chkAdopt.Size = New-Object System.Drawing.Size(730, 26)
$form.Controls.Add($chkAdopt)
$chkSite = New-Object System.Windows.Forms.CheckBox
$chkSite.Text = 'I confirm this computer and copier belong to Agilant HQ (approved main network)'
$chkSite.Location = New-Object System.Drawing.Point(18, 477)
$chkSite.Size = New-Object System.Drawing.Size(730, 26)
$form.Controls.Add($chkSite)
$form.Controls.Add((New-Lbl 'Optional: expected Wi-Fi SSID, configured locally from the approved network profile' 18 515))
$txtSsid = New-Txt 541
$form.Controls.Add($txtSsid)
$form.Controls.Add((New-Lbl 'Actual connected Wi-Fi SSID and TCP source address will appear in the preflight receipt.' 18 577))
$btnPlan = New-Btn '1. Preview & preflight' 18 610 220
$btnMap = New-Btn '2. Map / Repair' 252 610 220
$btnTest = New-Btn '3. Send test page' 486 610 262
$btnMap.Enabled = $false
$btnTest.Enabled = $false
$form.Controls.AddRange(@($btnPlan,$btnMap,$btnTest))
$lblState = New-Lbl 'Outcome: not started' 18 660
$form.Controls.Add($lblState)
$txtResult = New-Object System.Windows.Forms.TextBox
$txtResult.Location = New-Object System.Drawing.Point(18, 689)
$txtResult.Size = New-Object System.Drawing.Size(730, 170)
$txtResult.Multiline = $true; $txtResult.ReadOnly = $true
$txtResult.ScrollBars = 'Vertical'
$txtResult.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($txtResult)

function Refresh-Profiles([string]$Select = '') {
  $cmbProfiles.Items.Clear()
  [void]$cmbProfiles.Items.Add('(new printer)')
  foreach ($file in Get-ChildItem -LiteralPath $profilesDir -Filter '*.json' -File) {
    try {
      $data = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
      if ($data.SchemaVersion -eq 'sas-local-printer-profile/v1' -and $data.PrinterName) {
        [void]$cmbProfiles.Items.Add([string]$data.PrinterName)
      }
    } catch {}
  }
  $cmbProfiles.SelectedItem = if ($Select -and $cmbProfiles.Items.Contains($Select)) { $Select } else { '(new printer)' }
}
$cmbProfiles.Add_SelectedIndexChanged({
  if ([string]$cmbProfiles.SelectedItem -eq '(new printer)') { return }
  $path = Get-ProfilePath ([string]$cmbProfiles.SelectedItem)
  if (-not (Test-Path -LiteralPath $path)) { return }
  $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  $txtName.Text = $data.PrinterName
  $txtHost.Text = $data.HostOrAddress
  $txtPanel.Text = ''   # Security: never treat the stored IP as a fresh observation.
  $chkPanel.Checked = $false
  $chkOverride.Checked = $false
  $chkAdopt.Checked = $false
  $chkSite.Checked = $false
  $txtSsid.Text = [string]$data.ExpectedSsid
  if ($cmbDriver.Items.Contains([string]$data.DriverName)) {
    $cmbDriver.SelectedItem = $data.DriverName
  }
  $lblState.Text = 'Saved last-observed IP: ' + $data.LastObservedAddress + ' (historical hint, not verified now)'
  Reset-Plan
})
$btnSave.Add_Click({
  try {
    if ([string]::IsNullOrWhiteSpace($txtName.Text) -or -not $cmbDriver.SelectedItem) {
      throw 'Enter a name and select a driver first.'
    }
    $data = [ordered]@{
      SchemaVersion = 'sas-local-printer-profile/v1'
      PrinterName = $txtName.Text.Trim()
      HostOrAddress = $txtHost.Text.Trim()
      DriverName = [string]$cmbDriver.SelectedItem
      ExpectedSsid = $txtSsid.Text.Trim()
      LastObservedAddress = $txtPanel.Text.Trim()
      SavedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    $path = Get-ProfilePath $data.PrinterName
    $data | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
    Refresh-Profiles -Select $data.PrinterName
    $lblState.Text = 'Profile saved locally. Fresh panel confirmation is still required to map.'
  } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Profile error') | Out-Null }
})
$btnPlan.Add_Click({
  try {
    Reset-Plan
    $outcome = Invoke-Engine -Mode Plan -Confirmed $false
    if ($outcome.State -in @('READY_TO_MAP','READY_TO_ADOPT','READY_TO_ADOPT_STALE','ALREADY_MAPPED')) {
      $script:plannedFingerprint = Fingerprint
      $btnMap.Enabled = $true
      if ($outcome.State -eq 'ALREADY_MAPPED') { $btnTest.Enabled = $true }
    }
  } catch { $lblState.Text = 'Preview failed'; $txtResult.Text = $_.Exception.Message }
})
$btnMap.Add_Click({
  try {
    if ((Fingerprint) -ne $script:plannedFingerprint) {
      Reset-Plan
      throw 'Inputs changed since preflight. Preview the revised plan first.'
    }
    if (-not $chkPanel.Checked) {
      throw 'Read the current IP on the printer and check the physical confirmation box.'
    }
    if (-not $chkSite.Checked) { throw 'Confirm the approved Agilant HQ network/site before mapping.' }
    if ([System.Windows.Forms.MessageBox]::Show(
      'Apply this printer/driver/port mapping to THIS Windows computer?', 'Confirm local printer change',
      [System.Windows.Forms.MessageBoxButtons]::YesNo
    ) -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $outcome = Invoke-Engine -Mode Apply -Confirmed $true
    if ($outcome.State -in @('MAPPED_NOW','ALREADY_MAPPED')) {
      $btnTest.Enabled = $true
    }
  } catch { $lblState.Text = 'Mapping failed'; $txtResult.Text = $_.Exception.Message }
})
$btnTest.Add_Click({
  try {
    $outcome = Invoke-Engine -Mode TestPage -Confirmed $false
    if ($outcome.State -eq 'TEST_PAGE_SUBMITTED') {
      $answer = [System.Windows.Forms.MessageBox]::Show(
        'Did the test page physically emerge from the intended printer, with the expected output?',
        'Observe physical output', [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
      )
      $confirmed = $answer -eq [System.Windows.Forms.DialogResult]::Yes
      $runsDir = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\PrinterMapping\runs'
      [void](New-Item -ItemType Directory -Path $runsDir -Force)
      $observation = [ordered]@{
        SchemaVersion = 'sas-local-tcp-printer-physical-observation/v1'
        UseCaseId = 'agilant-hq.local-tcp-printer'
        PrinterName = $txtName.Text.Trim()
        EngineReceipt = $outcome.ReceiptPath
        Status = $(if ($confirmed) { 'OPERATOR_PHYSICAL_PRINT_CONFIRMED' } else { 'PHYSICAL_PRINT_NOT_CONFIRMED' })
        Method = 'user attestation in native SysAdminSuite GUI'
        ObservedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
      }
      $receipt = Join-Path $runsDir ('physical-observation-' + [guid]::NewGuid().ToString('N') + '.json')
      $observation | ConvertTo-Json | Set-Content -LiteralPath $receipt -Encoding UTF8
      $lblState.Text = $observation.Status
      $txtResult.Text = ($observation | ConvertTo-Json -Depth 4)
    }
  } catch { $lblState.Text = 'Test page failed'; $txtResult.Text = $_.Exception.Message }
})
foreach ($control in @($txtName,$txtHost,$txtPanel,$txtSsid)) {
  $control.Add_TextChanged({ Reset-Plan })
}
$cmbDriver.Add_SelectedIndexChanged({ Reset-Plan })
$chkOverride.Add_CheckedChanged({ Reset-Plan })
$chkAdopt.Add_CheckedChanged({ Reset-Plan })
Refresh-Profiles
[void]$form.ShowDialog()
