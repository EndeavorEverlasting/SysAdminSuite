#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$probePath = Join-Path $repoRoot 'scripts\Invoke-SasReadOnlyWorkstationProfileProbe.ps1'
$cmdPath = Join-Path $repoRoot 'Probe-TangentProfile.cmd'

foreach ($path in @($probePath,$cmdPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing Tangent/profile probe surface: $path" }
}

$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($probePath,[ref]$tokens,[ref]$errors)
if (@($errors).Count -gt 0) { throw ($errors | Out-String) }

$source = Get-Content -LiteralPath $probePath -Raw -Encoding UTF8
foreach ($forbidden in @(
    'Set-WmiInstance',
    'Invoke-WmiMethod',
    'Set-CimInstance',
    'Invoke-CimMethod',
    'schtasks',
    'sc.exe',
    'Set-ItemProperty',
    'New-Service',
    'Restart-Computer',
    'Stop-Computer'
)) {
    if ($source -match [regex]::Escape($forbidden)) {
        throw "Read-only workstation probe contains forbidden mutation surface: $forbidden"
    }
}
foreach ($required in @(
    "Win32_ComputerSystem",
    "Win32_ComputerSystemProduct",
    "Win32_BIOS",
    "Win32_BaseBoard",
    "Win32_OperatingSystem",
    "Win32_Processor",
    "Win32_SerialPort",
    "Win32_NetworkAdapterConfiguration",
    "SerialAndModelRequiredForHardwareComparison",
    "NONE_READ_ONLY_DISCOVERY",
    "TargetMutationPerformed = $false"
)) {
    if (-not $source.Contains($required)) { throw "Missing required comparison/read-only contract marker: $required" }
}

$cmdSource = Get-Content -LiteralPath $cmdPath -Raw -Encoding ASCII
if (-not $cmdSource.Contains('Invoke-SasReadOnlyWorkstationProfileProbe.ps1')) { throw 'Tangent CMD does not route to the canonical generic profile probe.' }
if (-not $cmdSource.Contains('TangentCandidate')) { throw 'Tangent CMD does not preserve candidate-only labeling.' }

$tempRoot = Join-Path $env:TEMP ('sas-workstation-profile-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $probePath -ComputerName $env:COMPUTERNAME -CandidateLabel 'FixtureCandidate' -OutputRoot $tempRoot -SkipNetworkGate
    if ($LASTEXITCODE -notin @(0,21)) { throw "Local fixture returned unexpected exit code: $LASTEXITCODE" }

    $json = Get-ChildItem -LiteralPath $tempRoot -Filter 'workstation_profile_*.json' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $json) { throw 'Local fixture did not emit structured workstation profile evidence.' }
    $rows = @(Get-Content -LiteralPath $json.FullName -Raw -Encoding UTF8 | ConvertFrom-Json)
    if ($rows.Count -ne 1) { throw "Expected one fixture row, got $($rows.Count)." }
    $row = $rows[0]
    if ([string]$row.SchemaVersion -ne 'sas-readonly-workstation-profile/v1') { throw 'Unexpected workstation profile schema.' }
    if ([string]$row.CandidateLabel -ne 'FixtureCandidate') { throw 'Fixture candidate label was not preserved.' }
    if ([bool]$row.TargetMutationPerformed) { throw 'Read-only fixture claims target mutation.' }
    if ([string]::IsNullOrWhiteSpace([string]$row.ObservedHostName)) { throw 'Fixture did not observe a hostname.' }
    if ([string]::IsNullOrWhiteSpace([string]$row.Model)) { throw 'Fixture did not observe a model.' }
    if ([string]$row.ProfileSelection -ne 'NONE_READ_ONLY_DISCOVERY') { throw 'Fixture selected a deployment profile.' }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: Tangent front door routes to a PS5.1-compatible, local-evidence-only, read-only workstation identity probe.'
