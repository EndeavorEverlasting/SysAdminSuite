$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$launcher = Join-Path $repoRoot 'Repair-Clipboard.cmd'
$engine = Join-Path $repoRoot 'scripts\Repair-SasClipboard.ps1'
$registry = Join-Path $repoRoot 'Config\operator-recipes.json'

$failures = New-Object System.Collections.Generic.List[string]

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { $failures.Add($Message) }
}

function Assert-NotContains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { $failures.Add($Message) }
}

if (-not (Test-Path -LiteralPath $launcher)) { $failures.Add('Repair-Clipboard.cmd is missing') }
if (-not (Test-Path -LiteralPath $engine)) { $failures.Add('scripts/Repair-SasClipboard.ps1 is missing') }
if (-not (Test-Path -LiteralPath $registry)) { $failures.Add('Config/operator-recipes.json is missing') }

if ($failures.Count -eq 0) {
    $launcherText = Get-Content -LiteralPath $launcher -Raw
    $engineText = Get-Content -LiteralPath $engine -Raw
    $registryData = Get-Content -LiteralPath $registry -Raw | ConvertFrom-Json

    Assert-Contains $launcherText 'where pwsh' 'Launcher must prefer PowerShell 7 when available'
    Assert-Contains $launcherText 'powershell\.exe' 'Launcher must fall back to Windows PowerShell'
    Assert-Contains $launcherText 'Repair-SasClipboard\.ps1' 'Launcher must delegate to Repair-SasClipboard.ps1'
    Assert-Contains $launcherText 'LOCALAPPDATA.*SysAdminSuite.*field-runs.*clipboard' 'Launcher must point technicians to clipboard evidence'

    Assert-Contains $engineText 'GetOpenClipboardWindow' 'Engine must capture the open clipboard HWND before reset'
    Assert-Contains $engineText 'GetWindowThreadProcessId' 'Engine must resolve clipboard HWND to PID'
    Assert-Contains $engineText '\$ownerPid' 'Engine must not collide with PowerShell automatic $PID'
    Assert-NotContains $engineText '\[uint32\]\$pid\b' 'Engine must not assign to PowerShell automatic $PID'
    Assert-Contains $engineText 'Get-CimInstance Win32_Service' 'Engine must inspect service ownership before restart'
    Assert-Contains $engineText 'Get-ServiceProcessOwnerIdentity' 'Engine must resolve the clipboard service process owner'
    Assert-Contains $engineText 'Expected exactly one cbdhsvc_\* instance owned by' 'Engine must fail closed on ambiguous per-user service selection'
    Assert-Contains $engineText 'Restart-Service -InputObject \$service -Force' 'Engine must restart only the selected current-user Clipboard User Service'
    Assert-Contains $engineText 'ProcessEvidenceError' 'Optional process evidence must be non-fatal'
    Assert-Contains $engineText 'finally' 'Engine must persist summary through a finally path'
    Assert-Contains $engineText 'Set-Clipboard -Value \$probe' 'Engine must perform a clipboard write probe'
    Assert-Contains $engineText 'Get-Clipboard -Raw' 'Engine must perform a clipboard read-back probe'
    Assert-Contains $engineText 'RecoveryPassed' 'Engine must gate success on complete recovery proof'
    Assert-Contains $engineText 'ServiceRestarted -and' 'Success must require service restart proof'
    Assert-Contains $engineText 'ClipboardCleared -and' 'Success must require clipboard clear proof'
    Assert-Contains $engineText 'VerificationPassed' 'Success must require round-trip verification'
    Assert-Contains $engineText 'summary\.json' 'Engine must persist a summary artifact'

    $recipe = @($registryData.recipes | Where-Object { $_.id -eq 'windows.clipboard.repair' })
    if ($recipe.Count -ne 1) {
        $failures.Add('operator recipe registry must contain exactly one windows.clipboard.repair entry')
    } elseif ($recipe[0].entrypoint -ne 'Repair-Clipboard.cmd') {
        $failures.Add('windows.clipboard.repair must point to Repair-Clipboard.cmd')
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'PASS: clipboard recovery launcher contracts satisfied.'
exit 0
