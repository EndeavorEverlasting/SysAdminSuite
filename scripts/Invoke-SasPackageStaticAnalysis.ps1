[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [switch]$CreateVenv,

    [Parameter(Mandatory = $false)]
    [string]$OfflineWheelhouse,

    [Parameter(Mandatory = $false)]
    [int]$MaxFiles = 50000,

    [Parameter(Mandatory = $false)]
    [long]$MaxTotalBytes = 107374182400,

    [Parameter(Mandatory = $false)]
    [int]$MaxContentBytes = 8388608
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$analyzer = Join-Path $repoRoot 'tools/package-analysis/analyze_package.py'
$requirements = Join-Path $repoRoot 'tools/package-analysis/requirements-optional.txt'
$venvRoot = Join-Path $repoRoot '.venv/package-analysis'

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Input path does not exist: $InputPath"
}
if (-not (Test-Path -LiteralPath $analyzer -PathType Leaf)) {
    throw "Analyzer is missing: $analyzer"
}
if ($OfflineWheelhouse -and -not $CreateVenv) {
    throw '-OfflineWheelhouse requires -CreateVenv.'
}
if ($OfflineWheelhouse -and -not (Test-Path -LiteralPath $OfflineWheelhouse -PathType Container)) {
    throw "Offline wheelhouse does not exist: $OfflineWheelhouse"
}

if (-not $OutputRoot) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputRoot = Join-Path $repoRoot "survey/output/package_static_analysis/$stamp"
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
}
if (-not $python) {
    throw 'Python 3 is required but was not found on PATH.'
}
$pythonCommand = $python.Source
$pythonPrefix = @()
if ($python.Name -eq 'py.exe' -or $python.Name -eq 'py') {
    $pythonPrefix = @('-3')
}

if ($CreateVenv) {
    if (-not (Test-Path -LiteralPath $venvRoot -PathType Container)) {
        & $pythonCommand @pythonPrefix -m venv $venvRoot
        if ($LASTEXITCODE -ne 0) { throw "Virtual environment creation failed with exit code $LASTEXITCODE." }
    }
    $venvPython = Join-Path $venvRoot 'Scripts/python.exe'
    if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
        throw "Virtual environment Python is missing: $venvPython"
    }
    $pythonCommand = $venvPython
    $pythonPrefix = @()

    if ($OfflineWheelhouse) {
        & $pythonCommand -m pip install --disable-pip-version-check --no-index --find-links $OfflineWheelhouse -r $requirements
        if ($LASTEXITCODE -ne 0) { throw "Offline optional dependency installation failed with exit code $LASTEXITCODE." }
    }
}

Write-Host 'PACKAGE STATIC ANALYSIS'
Write-Host "Input: $InputPath"
Write-Host "Output: $OutputRoot"
Write-Host 'Posture: static-only; no package execution, extraction, network activity, or host mutation'

& $pythonCommand @pythonPrefix $analyzer `
    --input $InputPath `
    --output-dir $OutputRoot `
    --max-files $MaxFiles `
    --max-total-bytes $MaxTotalBytes `
    --max-content-bytes $MaxContentBytes
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    throw "Package static analysis completed with exit code $exitCode. Review $OutputRoot."
}

Write-Host "[PASS] Static package evidence written to $OutputRoot"
