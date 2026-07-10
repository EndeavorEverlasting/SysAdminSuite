[CmdletBinding()]
param(
  [string]$Step
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$packPath = Join-Path $repoRoot 'configs\hotfix-command-packs\cybernet-com-port-repair.pack.json'
$fieldHotfixGuiPath = Join-Path $repoRoot 'GUI\Start-FieldHotfixesGui.ps1'
$outlinePath = Join-Path $repoRoot 'docs\field-hotfixes\cybernet-com-port-qr-pack.md'

function Get-ComQrPack {
  if (-not (Test-Path -LiteralPath $packPath)) { throw "Cybernet COM QR pack not found: $packPath" }
  return Get-Content -LiteralPath $packPath -Raw | ConvertFrom-Json
}

function New-FieldHotfixManifestFromSnippet {
  param(
    [Parameter(Mandatory)]$Pack,
    [Parameter(Mandatory)]$Snippet
  )

  [pscustomobject]@{
    schema_version = '1.0.0'
    command_id = [string]$Snippet.command_id
    title = [string]$Snippet.title
    status = 'approved-field-hotfix'
    version = [string]$Pack.version
    risk_level = [string]$Snippet.risk_level
    requires_operator_confirmation = $true
    intended_operator_position = 'standing-at-target'
    delivery_modes = @('admin-gui-qr-display','suite-clone-local-qr-generation')
    applies_to = @('Cybernet devices where FINTEK serial hardware is present but Windows COM ports are numbered unexpectedly')
    preconditions = @(
      'A technician is physically standing in front of the target Cybernet',
      'Command Prompt is open as Administrator for capture, registry export/reset, or reboot snippets',
      'The device is not finalized for clinical app binding while COM mapping is still being corrected'
    )
    forbidden_use = @(
      'Do not use as a general Windows repair workflow',
      'Do not run silently from the admin box',
      'Do not use after final clinical app/device COM binding unless an operator explicitly approves it'
    )
    scan_instructions = @(
      'Open Command Prompt as Administrator on the Cybernet',
      [string]$Snippet.operator_note,
      'Scan this QR payload into the Command Prompt window',
      'Press Enter if the scanner does not send Enter automatically'
    )
    cmd_payload = [string]$Snippet.cmd_payload
    powershell_payload = [string]$Snippet.powershell_payload
    qr_payloads = [pscustomobject]@{
      cmd_shift_f10 = [string]$Snippet.cmd_payload
      powershell_console = [string]$Snippet.powershell_payload
    }
    expected_result = [string]$Snippet.expected_result
    rollback_note = 'This step is either evidence-only or part of the bounded COM repair workflow. Reimage or restore the exported COM Name Arbiter key only if directed by a lead.'
    evidence_to_capture = @(
      'target asset tag or hostname label',
      'timestamp',
      'operator name or initials',
      'whether COM ports are visible as expected after the step'
    )
  }
}

function Invoke-ComQrSnippet {
  param(
    [Parameter(Mandatory)]$Pack,
    [Parameter(Mandatory)]$Snippet
  )

  if (-not (Test-Path -LiteralPath $fieldHotfixGuiPath)) {
    throw "Field Hotfixes GUI not found: $fieldHotfixGuiPath"
  }

  $manifest = New-FieldHotfixManifestFromSnippet -Pack $Pack -Snippet $Snippet
  $tempRoot = Join-Path $env:TEMP 'SysAdminSuite\CybernetComQrPack'
  New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
  $safeStep = ([string]$Snippet.step) -replace '[^0-9A-Za-z_-]', '_'
  $manifestPath = Join-Path $tempRoot ("cybernet-com-$safeStep.json")
  $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

  Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile',
    '-STA',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    "`"$fieldHotfixGuiPath`"",
    '-ManifestPath',
    "`"$manifestPath`""
  ) -Wait | Out-Null
}

function Show-ComQrMenu {
  param([Parameter(Mandatory)]$Pack)

  while ($true) {
    Clear-Host
    Write-Host 'SysAdminSuite - Cybernet COM Port QR Pack'
    Write-Host ''
    Write-Host 'Use on the local Cybernet only. Open Command Prompt as Administrator before scanning snippets.'
    Write-Host ''
    foreach ($snippet in $Pack.sequence) {
      Write-Host ("{0,2}  {1} [{2}]" -f $snippet.step, $snippet.title, $snippet.risk_level)
    }
    Write-Host ''
    Write-Host 'O   Open package outline'
    Write-Host 'Q   Quit'
    Write-Host ''

    $choice = Read-Host 'Select QR snippet'
    if ([string]::IsNullOrWhiteSpace($choice)) { continue }
    if ($choice -match '^(?i)q$') { return }
    if ($choice -match '^(?i)o$') {
      if (Test-Path -LiteralPath $outlinePath) { Start-Process -FilePath $outlinePath | Out-Null }
      continue
    }

    $normalized = if ($choice -match '^\d$') { '0' + $choice } else { $choice }
    $snippet = @($Pack.sequence | Where-Object { $_.step -eq $normalized }) | Select-Object -First 1
    if (-not $snippet) {
      Write-Host ''
      Write-Warning "Unknown selection: $choice"
      pause
      continue
    }

    Invoke-ComQrSnippet -Pack $Pack -Snippet $snippet
  }
}

$pack = Get-ComQrPack
if ($Step) {
  $normalizedStep = if ($Step -match '^\d$') { '0' + $Step } else { $Step }
  $snippet = @($pack.sequence | Where-Object { $_.step -eq $normalizedStep }) | Select-Object -First 1
  if (-not $snippet) { throw "Unknown Cybernet COM QR pack step: $Step" }
  Invoke-ComQrSnippet -Pack $pack -Snippet $snippet
  return
}

Show-ComQrMenu -Pack $pack
