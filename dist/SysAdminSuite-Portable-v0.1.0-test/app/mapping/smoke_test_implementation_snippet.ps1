Get-Content .\mapping\csv\hosts.txt |
  ? { $_ -and $_ -notmatch '^\s*#' } |
  Select-Object -First 3 |
  Set-Content -Encoding UTF8 .\mapping\csv\hosts_smoke.txt

$Smoke = Resolve-Path .\mapping\csv\hosts_smoke.txt
pwsh -NoProfile .\mapping\RPM-Recon.ps1 `
  -HostsPath $Smoke `
  -MaxParallel 3 `
  -MaxWaitSeconds 60 `
  -PollSeconds 3
