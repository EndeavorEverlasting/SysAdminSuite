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
    [int]$MaxContentBytes = 8388608,

    [Parameter(Mandatory = $false)]
    [int]$MaxSemanticBytes = 16777216
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$baseWrapper = Join-Path $repoRoot 'scripts/Invoke-SasPackageStaticAnalysis.ps1'
$semanticAnalyzer = Join-Path $repoRoot 'tools/package-analysis/enrich_package_semantics.py'
$venvPython = Join-Path $repoRoot '.venv/package-analysis/Scripts/python.exe'

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Input path does not exist: $InputPath"
}
if (-not (Test-Path -LiteralPath $baseWrapper -PathType Leaf)) {
    throw "Base package analyzer wrapper is missing: $baseWrapper"
}
if (-not (Test-Path -LiteralPath $semanticAnalyzer -PathType Leaf)) {
    throw "Semantic analyzer is missing: $semanticAnalyzer"
}
if ($MaxFiles -le 0 -or $MaxTotalBytes -le 0 -or $MaxContentBytes -le 0 -or $MaxSemanticBytes -le 0) {
    throw 'All analysis limits must be positive integers.'
}
if (-not $OutputRoot) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputRoot = Join-Path $repoRoot "survey/output/package_semantic_analysis/$stamp"
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$baseParams = @{
    InputPath = $InputPath
    OutputRoot = $OutputRoot
    MaxFiles = $MaxFiles
    MaxTotalBytes = $MaxTotalBytes
    MaxContentBytes = $MaxContentBytes
}
if ($CreateVenv) { $baseParams.CreateVenv = $true }
if ($OfflineWheelhouse) { $baseParams.OfflineWheelhouse = $OfflineWheelhouse }

Write-Host 'PACKAGE SEMANTIC ANALYSIS'
Write-Host "Input: $InputPath"
Write-Host "Output: $OutputRoot"
Write-Host 'Phase 1: canonical static inventory and hash evidence'
& $baseWrapper @baseParams

$baseResult = Join-Path $OutputRoot 'package_analysis.json'
if (-not (Test-Path -LiteralPath $baseResult -PathType Leaf)) {
    throw "Base package result is missing: $baseResult"
}

$pythonCommand = $null
$pythonPrefix = @()
if ($CreateVenv -and (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    $pythonCommand = $venvPython
} else {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $python) { throw 'Python 3 is required but was not found on PATH.' }
    $pythonCommand = $python.Source
    if ($python.Name -eq 'py.exe' -or $python.Name -eq 'py') { $pythonPrefix = @('-3') }
}

Write-Host 'Phase 2: hash-verified semantic enrichment and harness requirements'
& $pythonCommand @pythonPrefix $semanticAnalyzer `
    --input $InputPath `
    --base-result $baseResult `
    --output-dir $OutputRoot `
    --max-files $MaxFiles `
    --max-semantic-bytes $MaxSemanticBytes
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "Package semantic analysis completed with exit code $exitCode. Review $OutputRoot."
}
Write-Host "[PASS] Static and semantic package evidence written to $OutputRoot"
