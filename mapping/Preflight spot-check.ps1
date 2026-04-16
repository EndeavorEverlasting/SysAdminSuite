# Preflight spot-check
'WLS111WCC064','WLS111WCC063','WLS111WCC062' | % { Test-Connection $_ -Count 1 -Quiet; Test-Path "\\$_\ADMIN$" }

# Live smoke on 3 hosts
Get-Content .\mapping\csv\hosts.txt | ? { $_ -and $_ -notmatch '^\s*#' } |
  Select -First 3 | Set-Content -Enc UTF8 .\mapping\csv\hosts_smoke.txt
$Smoke = Resolve-Path .\mapping\csv\hosts_smoke.txt
pwsh -NoProfile .\mapping\RPM-Recon.ps1 -HostsPath $Smoke -MaxParallel 3 -MaxWaitSeconds 60 -PollSeconds 3

# Full rollout (batched)
pwsh -NoProfile .\Run-164.ps1 -HostsPath .\mapping\csv\hosts.txt -BatchSize 24 -MaxParallel 12 -MaxWaitSeconds 60 -PollSeconds 3 -DelayBetweenBatches 20
