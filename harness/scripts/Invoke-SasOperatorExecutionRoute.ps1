#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetBase64
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$registryPath = Join-Path $repoRoot 'harness\api\operator-execution-route-registry.json'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    throw "Operator execution route registry is missing: $registryPath"
}

try {
    $targetBytes = [Convert]::FromBase64String($TargetBase64)
    $target = [Text.Encoding]::UTF8.GetString($targetBytes)
}
catch {
    [Console]::Error.WriteLine('SAS_OPERATOR_ROUTE_TARGET_ENCODING_INVALID')
    exit 2
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$routes = @($registry.routes | Where-Object { [string]$_.id -eq 'autologon-remote-crash-safe' })
if ($routes.Count -ne 1) {
    throw "Expected one autologon-remote-crash-safe route, found $($routes.Count)."
}
$route = $routes[0]

$pattern = [string]$route.target_validation_pattern
if ([string]::IsNullOrWhiteSpace($pattern) -or $target -notmatch $pattern) {
    [Console]::Error.WriteLine('SAS_OPERATOR_ROUTE_TARGET_INVALID')
    exit 2
}

foreach ($relative in @($route.path_resolution.required_files | ForEach-Object { [string]$_ })) {
    $candidate = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Required operator route file missing: $candidate"
    }
}

$entrypoint = [string]$route.operator_entrypoint
if ([string]::IsNullOrWhiteSpace($entrypoint)) {
    throw 'Operator route entrypoint is empty.'
}
$launcher = Join-Path $repoRoot $entrypoint
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "Operator route entrypoint is missing: $launcher"
}

Write-Host "Resolved SysAdminSuite repo: $repoRoot" -ForegroundColor Cyan
Write-Host "Operator front door: $entrypoint" -ForegroundColor Cyan
Write-Host "AutoLogon target: $target" -ForegroundColor Cyan

Set-Location -LiteralPath $repoRoot
& $launcher $target
exit [int]$LASTEXITCODE
