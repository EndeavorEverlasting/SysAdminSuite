[CmdletBinding()]
param(
    [string]$PolicyPath
)

$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $PolicyPath) {
    $PolicyPath = Join-Path $RepoRoot 'config/log-operation-policy.json'
}
$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
$mustForbid = 'LIVE_READ_HOST_LOG','EXPORT_HOST_LOG','CLEAR_LOG','DELETE_LOG','MUTATE_LOG','DISABLE_LOGGING','SUPPRESS_AUDIT'
foreach ($op in $mustForbid) { if ($policy.operations.$op.decision -ne 'forbidden') { throw "$op must be forbidden" } }
'Log operation policy validation passed.'
