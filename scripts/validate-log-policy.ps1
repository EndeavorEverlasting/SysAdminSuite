[CmdletBinding()]
param([string]$PolicyPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/log-operation-policy.json'))
$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
$mustForbid = 'LIVE_READ_HOST_LOG','EXPORT_HOST_LOG','CLEAR_LOG','DELETE_LOG','MUTATE_LOG','DISABLE_LOGGING','SUPPRESS_AUDIT'
foreach ($op in $mustForbid) { if ($policy.operations.$op.decision -ne 'forbidden') { throw "$op must be forbidden" } }
'Log operation policy validation passed.'
