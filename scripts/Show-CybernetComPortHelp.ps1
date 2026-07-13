[CmdletBinding()]
param(
  [ValidateSet('menu', 'status', 'overview', 'parser', 'dry-run', 'inspect', 'qr', 'apply', 'diagnostics', 'setup-loop')]
  [string]$Topic = 'menu',
  [switch]$Copy
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$readinessPath = Join-Path $repoRoot 'docs\handoff\cybernet-com-autofix-release-readiness.md'

function Write-Heading {
  param([Parameter(Mandatory)][string]$Text)
  Write-Host ''
  Write-Host ('=' * 72)
  Write-Host $Text
  Write-Host ('=' * 72)
}

function Copy-CommandBlock {
  param([Parameter(Mandatory)][string[]]$Commands)

  if ($Commands.Count -eq 0) {
    Write-Host 'Nothing to copy for this topic.'
    return
  }

  $text = $Commands -join [Environment]::NewLine
  $setClipboard = Get-Command Set-Clipboard -ErrorAction SilentlyContinue
  if ($setClipboard) {
    $text | Set-Clipboard
  }
  else {
    $text | clip.exe
  }
  Write-Host 'COPIED TO CLIPBOARD'
}

function Get-LocalReadinessLabel {
  if (-not (Test-Path -LiteralPath $readinessPath)) {
    return 'UNKNOWN - release-readiness document is missing.'
  }

  $content = Get-Content -LiteralPath $readinessPath -Raw
  if ($content -match 'HOLD\s*-\s*DO NOT MERGE') {
    return 'HOLD - live Cybernet proof is still required.'
  }
  if ($content -match '(?im)^\s*(GO|READY)\b') {
    return 'READY marker found - still confirm the full release-readiness document.'
  }
  return 'REVIEW REQUIRED - no unambiguous HOLD or READY marker was found.'
}

$topics = [ordered]@{
  overview = [pscustomobject]@{
    Title = 'Which COM tool should I use?'
    Commands = @(
      'Run-CybernetComPortHelp.cmd status',
      'Run-CybernetComPortAutoFix-DryRun.cmd',
      '.\scripts\Inspect-CybernetComPortAutoFixEvidence.ps1',
      'Run-CybernetComPortQrPack.cmd'
    )
    Notes = @(
      'Use dry-run first on an approved, non-finalized Cybernet showing COM3-COM6.',
      'Use the evidence inspector after dry-run. Required success text: REGISTRY BACKUPS VALIDATED.',
      'Use the QR pack when the suite is on the admin/tech box and the operator is standing at the target.',
      'Apply is a separate approved action. Do not continue final app binding until COM1-COM4 sticks after reboot.'
    )
  }
  parser = [pscustomobject]@{
    Title = 'Verify the tracked PowerShell script parses'
    Commands = @('.\scripts\Test-CybernetComPortAutoFixParser.ps1')
    Notes = @('The only successful result is PARSE OK.')
  }
  'dry-run' = [pscustomobject]@{
    Title = 'Capture evidence and preview the COM mapping'
    Commands = @('Run-CybernetComPortAutoFix-DryRun.cmd')
    Notes = @(
      'Pass no arguments.',
      'Dry-run exports the registry backups and stops before PortName changes or reboot.'
    )
  }
  inspect = [pscustomobject]@{
    Title = 'Validate the latest AutoFix evidence'
    Commands = @('.\scripts\Inspect-CybernetComPortAutoFixEvidence.ps1')
    Notes = @(
      'Required success text: REGISTRY BACKUPS VALIDATED.',
      'All five .reg files and autofix-summary.json must exist and be nonempty.'
    )
  }
  qr = [pscustomobject]@{
    Title = 'Open the scannable COM snippet pack'
    Commands = @('Run-CybernetComPortQrPack.cmd')
    Notes = @(
      'Use while the operator is physically standing at the Cybernet.',
      'The QR pack includes read-only evidence snippets plus guarded reset/reboot steps.'
    )
  }
  apply = [pscustomobject]@{
    Title = 'Apply the COM3-COM6 to COM1-COM4 repair'
    Commands = @('Run-CybernetComPortAutoFix.cmd')
    Notes = @(
      'APPROVAL REQUIRED.',
      'Use only after parser, dry-run, and evidence inspection succeed on an approved non-finalized Cybernet.',
      'The apply launcher resets COM reservations, updates PortName values, writes evidence, and reboots.'
    )
  }
  diagnostics = [pscustomobject]@{
    Title = 'Read-only COM diagnostics and evidence shortcuts'
    Commands = @(
      'reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM',
      'pnputil /enum-devices /class Ports',
      'pnputil /enum-devices /class MultiPortSerial',
      'cmd /c "set devmgr_show_nonpresent_devices=1&&start devmgmt.msc"',
      'explorer C:\Temp\CybernetCOM'
    )
    Notes = @(
      'These commands inspect local COM state or open the evidence folder.',
      'In Device Manager, choose View > Show hidden devices. Do not remove the active FINTEK adapter.'
    )
  }
  'setup-loop' = [pscustomobject]@{
    Title = 'Separate use case: Windows setup restart/error loop'
    Commands = @(
      'Run-FieldHotfixesGui.cmd',
      'reg add HKLM\SYSTEM\Setup\Status\ChildCompletion /v setup.exe /t REG_DWORD /d 3 /f && shutdown /r /t 0'
    )
    Notes = @(
      'This is not the COM repair.',
      'At the failed setup screen, press Shift+F10 and use the Cybernet Windows Setup Completion Flag QR.',
      'Use only on the Windows setup unexpected-restart/error screen before final app binding.'
    )
  }
}

function Show-Status {
  Write-Heading 'Cybernet COM Port Rollout Status'
  Write-Host ("Local readiness: {0}" -f (Get-LocalReadinessLabel))
  Write-Host ''
  Write-Host 'Required repo entrypoints:'
  $required = @(
    'Run-CybernetComPortAutoFix-DryRun.cmd',
    'Run-CybernetComPortAutoFix.cmd',
    'Run-CybernetComPortQrPack.cmd',
    'scripts\Test-CybernetComPortAutoFixParser.ps1',
    'scripts\Inspect-CybernetComPortAutoFixEvidence.ps1'
  )
  foreach ($relative in $required) {
    $present = Test-Path -LiteralPath (Join-Path $repoRoot $relative)
    $marker = if ($present) { 'PRESENT' } else { 'MISSING' }
    Write-Host ("[{0}] {1}" -f $marker, $relative)
  }
  Write-Host ''
  Write-Host ("Release-readiness document: {0}" -f $readinessPath)
  Write-Host 'This status check does not run a fix or prove live Cybernet behavior.'
}

function Show-Topic {
  param([Parameter(Mandatory)][string]$Name)

  if ($Name -eq 'status') {
    Show-Status
    return
  }

  $item = $topics[$Name]
  if ($null -eq $item) {
    throw "Unknown tutorial topic: $Name"
  }

  Write-Heading $item.Title
  foreach ($note in $item.Notes) {
    Write-Host ("- {0}" -f $note)
  }
  if ($item.Commands.Count -gt 0) {
    Write-Host ''
    Write-Host 'Copy-ready command(s):'
    for ($i = 0; $i -lt $item.Commands.Count; $i++) {
      Write-Host ('[{0}] {1}' -f ($i + 1), $item.Commands[$i])
    }
  }

  if ($Copy) {
    Copy-CommandBlock -Commands $item.Commands
  }
}

function Show-Menu {
  Write-Heading 'SysAdminSuite Cybernet COM Port Help'
  Write-Host 'This tutorial prints or copies commands. It does not run them.'
  Write-Host ''
  Write-Host '[1] Rollout status'
  Write-Host '[2] Which tool should I use?'
  Write-Host '[3] Parser check'
  Write-Host '[4] Dry-run'
  Write-Host '[5] Evidence inspector'
  Write-Host '[6] QR snippet pack'
  Write-Host '[7] Apply command and guardrails'
  Write-Host '[8] Read-only diagnostic snippets'
  Write-Host '[9] Separate setup-loop registry flag use case'
  Write-Host '[Q] Quit'
  Write-Host ''
  $choice = Read-Host 'Choose one topic'
  $selection = switch ($choice.ToUpperInvariant()) {
    '1' { 'status' }
    '2' { 'overview' }
    '3' { 'parser' }
    '4' { 'dry-run' }
    '5' { 'inspect' }
    '6' { 'qr' }
    '7' { 'apply' }
    '8' { 'diagnostics' }
    '9' { 'setup-loop' }
    'Q' { return }
    default { throw "Unknown menu choice: $choice" }
  }
  Show-Topic -Name $selection
}

if ($Topic -eq 'menu') {
  Show-Menu
}
else {
  Show-Topic -Name $Topic
}
