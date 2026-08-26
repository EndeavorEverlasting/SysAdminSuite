#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:TZ = 'UTC'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checkoutValue = @(& git -C $repoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
$checkoutSha = if ([int]$global:LASTEXITCODE -ne 0 -or $checkoutValue.Count -eq 0) {
    'UNKNOWN'
} else {
    ([string]$checkoutValue[0]).Trim()
}
$candidateSha = if (-not [string]::IsNullOrWhiteSpace([string]$env:SAS_REFRESH_CANDIDATE_SHA)) {
    ([string]$env:SAS_REFRESH_CANDIDATE_SHA).Trim()
} else {
    $checkoutSha
}
Write-Host "SAS_REFRESH_TEST_FLOOR_CANDIDATE_SHA=$candidateSha" -ForegroundColor Cyan
Write-Host "SAS_REFRESH_TEST_FLOOR_CHECKOUT_SHA=$checkoutSha" -ForegroundColor DarkCyan

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

Write-Host "PASS: deterministic SAS refresh Windows test floor for candidate $candidateSha (checkout $checkoutSha)" -ForegroundColor Green
exit 0
