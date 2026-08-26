#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:TZ = 'UTC'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sha = if (-not [string]::IsNullOrWhiteSpace([string]$env:GITHUB_SHA)) {
    [string]$env:GITHUB_SHA
} else {
    $value = @(& git -C $repoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
    if ([int]$global:LASTEXITCODE -ne 0 -or $value.Count -eq 0) { 'UNKNOWN' } else { ([string]$value[0]).Trim() }
}
Write-Host "SAS_REFRESH_TEST_FLOOR_CANDIDATE_SHA=$sha" -ForegroundColor Cyan

$tests = @(
    'SasOperatorRefreshNativeStderr.Tests.ps1',
    'SasOperatorRefreshObjectCompleteness.Tests.ps1'
)
foreach ($name in $tests) {
    $path = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required SAS refresh test is missing: $path"
    }
    Write-Host "RUNNING: $name" -ForegroundColor Cyan
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $path
    $exitCode = [int]$global:LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "SAS refresh deterministic test floor failed in $name (exit $exitCode)."
    }
}

Write-Host "PASS: deterministic SAS refresh Windows test floor at $sha" -ForegroundColor Green
exit 0
