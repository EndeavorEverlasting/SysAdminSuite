$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$launcher = Join-Path $repoRoot 'Repair-Clipboard.cmd'
$engine = Join-Path $repoRoot 'scripts\Repair-SasClipboard.ps1'

$failures = New-Object System.Collections.Generic.List[string]

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { $failures.Add($Message) }
}

if (-not (Test-Path -LiteralPath $launcher)) { $failures.Add('Repair-Clipboard.cmd is missing') }
if (-not (Test-Path -LiteralPath $engine)) { $failures.Add('scripts/Repair-SasClipboard.ps1 is missing') }

if ($failures.Count -eq 0) {
    $launcherText = Get-Content -LiteralPath $launcher -Raw
    $engineText = Get-Content -LiteralPath $engine -Raw

    Assert-Contains $launcherText 'Repair-SasClipboard\.ps1' 'Launcher must delegate to Repair-SasClipboard.ps1'
    Assert-Contains $launcherText 'LOCALAPPDATA.*SysAdminSuite.*field-runs.*clipboard' 'Launcher must point technicians to clipboard evidence'
    Assert-Contains $engineText 'GetOpenClipboardWindow' 'Engine must capture the open clipboard HWND before reset'
    Assert-Contains $engineText 'GetWindowThreadProcessId' 'Engine must resolve clipboard HWND to PID'
    Assert-Contains $engineText "Get-Service -Name 'cbdhsvc\*'" 'Engine must discover the per-user Clipboard User Service dynamically'
    Assert-Contains $engineText 'Restart-Service -Force' 'Engine must restart the Clipboard User Service'
    Assert-Contains $engineText 'Set-Clipboard -Value \$probe' 'Engine must perform a clipboard write probe'
    Assert-Contains $engineText 'Get-Clipboard -Raw' 'Engine must perform a clipboard read-back probe'
    Assert-Contains $engineText 'VerificationPassed' 'Engine must gate success on round-trip verification'
    Assert-Contains $engineText 'summary\.json' 'Engine must persist a summary artifact'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'PASS: clipboard recovery launcher contracts satisfied.'
exit 0
