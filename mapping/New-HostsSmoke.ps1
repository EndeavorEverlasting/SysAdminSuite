param(
  [string]$HostsPath = ".\mapping\csv\hosts.txt",
  [string]$OutPath   = ".\mapping\csv\hosts_smoke.txt",
  [int]$Count = 3
)
$ResolvedHosts = Resolve-Path -Path $HostsPath -ErrorAction Stop
$parent = Split-Path -Parent $OutPath
if ($parent) { $null = New-Item -ItemType Directory -Force -Path $parent }

Get-Content -Path $ResolvedHosts |
  Where-Object { $_ -and $_ -notmatch '^\s*#' } |
  ForEach-Object { $_.Trim() } |
  Select-Object -First $Count |
  Set-Content -Encoding UTF8 $OutPath
Write-Host "Wrote smoke list → $OutPath"
