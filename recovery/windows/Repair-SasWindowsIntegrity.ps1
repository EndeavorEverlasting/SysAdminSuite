[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-RepairStep {
    param([string]$Name, [string]$FilePath, [string[]]$ArgumentList)
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    $lines = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { Write-Host "$_"; "$_" })
    $code = $LASTEXITCODE
    [pscustomobject]@{ name = $Name; exit_code = $code; output = $lines }
}

$plan = @(
    'DISM.exe /Online /Cleanup-Image /RestoreHealth',
    'sfc.exe /scannow',
    'DISM.exe /Online /Cleanup-Image /ScanHealth',
    'sfc.exe /verifyonly'
)

if (-not $Apply) {
    [pscustomobject]@{
        status = 'plan_only'
        requires_administrator = $true
        sequence = $plan
        note = 'Rerun with -Apply to execute. A successful DISM exit code is not the same as a clean final ScanHealth state.'
    } | ConvertTo-Json -Depth 5
    exit 0
}

if (-not (Test-IsAdministrator)) { throw 'Administrator PowerShell is required for -Apply.' }

$steps = New-Object System.Collections.Generic.List[object]
$restore = Invoke-RepairStep -Name 'DISM RestoreHealth' -FilePath 'DISM.exe' -ArgumentList @('/Online','/Cleanup-Image','/RestoreHealth')
$steps.Add($restore)
if ($restore.exit_code -ne 0) { throw "DISM RestoreHealth failed with exit code $($restore.exit_code); SFC was not started." }

$sfcRepair = Invoke-RepairStep -Name 'SFC ScanNow' -FilePath 'sfc.exe' -ArgumentList @('/scannow')
$steps.Add($sfcRepair)
$scan = Invoke-RepairStep -Name 'DISM ScanHealth verification' -FilePath 'DISM.exe' -ArgumentList @('/Online','/Cleanup-Image','/ScanHealth')
$steps.Add($scan)
$sfcVerify = Invoke-RepairStep -Name 'SFC VerifyOnly' -FilePath 'sfc.exe' -ArgumentList @('/verifyonly')
$steps.Add($sfcVerify)

$dismText = ($scan.output -join "`n")
$sfcText = ($sfcVerify.output -join "`n")
$dismState = if ($dismText -match 'No component store corruption detected') { 'clean' } elseif ($dismText -match 'component store is repairable') { 'repairable' } else { 'unknown' }
$sfcState = if ($sfcText -match 'did not find any integrity violations') { 'clean' } elseif ($sfcText -match 'found integrity violations') { 'violations' } else { 'unknown' }

$result = [pscustomobject]@{
    schema_version = '1.0'
    completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    dism_final_state = $dismState
    sfc_final_state = $sfcState
    steps = @($steps)
    proof_ceiling = 'This proves only the observed DISM/SFC servicing results. It does not prove application health, firmware health, disk health, or a successful backup restore.'
}

$json = $result | ConvertTo-Json -Depth 8
if ($ReportPath) {
    $parent = Split-Path -Parent $ReportPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-Content -LiteralPath $ReportPath -Value $json -Encoding UTF8
}
$json

if ($restore.exit_code -ne 0 -or $sfcRepair.exit_code -ne 0 -or $scan.exit_code -ne 0 -or $sfcVerify.exit_code -ne 0 -or $dismState -ne 'clean' -or $sfcState -ne 'clean') {
    exit 2
}
exit 0
