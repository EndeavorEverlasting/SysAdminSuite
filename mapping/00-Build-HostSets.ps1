#requires -version 5.1
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent  # mapping\
$csv  = Join-Path $root 'csv'
$allPath = Join-Path $csv 'hosts.txt'

if (!(Test-Path $allPath)) { throw "Missing: $allPath" }

$all = Get-Content -LiteralPath $allPath | Where-Object { $_ -and $_ -notmatch '^\s*#' } | Sort-Object -Unique
$reachable = foreach ($h in $all) {
  if (Test-Path "\\$h\ADMIN$") { $h }
}
$unreach = $all | Where-Object { $_ -notin $reachable }

$reachPath = Join-Path $csv 'hosts_reachable.txt'
$unreachPath = Join-Path $csv 'hosts_unreachable.txt'
$reachable | Set-Content -Encoding ascii -LiteralPath $reachPath
$unreach   | Set-Content -Encoding ascii -LiteralPath $unreachPath

"{0} total | {1} reachable | {2} missing" -f $all.Count, $reachable.Count, $unreach.Count
"➡  Wrote: $reachPath"
"➡  Wrote: $unreachPath"
