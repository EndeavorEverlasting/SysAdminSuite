[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$BaseResult,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [int]$MaxFiles = 50000
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$verifier = Join-Path $repoRoot 'tools/package-analysis/verify_dotnet_strong_name.py'

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Input path does not exist: $InputPath"
}
if (-not (Test-Path -LiteralPath $BaseResult -PathType Leaf)) {
    throw "Base package result is missing: $BaseResult"
}
if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) {
    throw "Strong-name verifier is missing: $verifier"
}
if ($MaxFiles -le 0) {
    throw 'MaxFiles must be a positive integer.'
}
if (-not $OutputRoot) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputRoot = Join-Path $repoRoot "survey/output/package_strong_name_verification/$stamp"
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Python 3 is required but was not found on PATH.' }

Write-Host 'PACKAGE STRONG-NAME VERIFICATION'
Write-Host "Input: $InputPath"
Write-Host "Base result: $BaseResult"
Write-Host "Output: $OutputRoot"

& $python.Source $verifier `
    --input $InputPath `
    --base-result $BaseResult `
    --output-dir $OutputRoot `
    --max-files $MaxFiles
exit $LASTEXITCODE
