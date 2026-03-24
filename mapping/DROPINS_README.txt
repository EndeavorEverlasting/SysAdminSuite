# Drop-ins
- RPM-Recon.annotated.ps1 - controller (longer wait, safer cleanup, seed option)
- Enforce-Mapping-SingleHost.ps1 - one-off enforcer for WLS111WCC094 -> \\SWBPNHPHPS01V\LS111-WCC65

## Typical runs
# smoke set
Get-Content .\csv\hosts.txt | ? { $_ -and $_ -notlike '#*' } | Select -First 3 | Set-Content .\csv\hosts_smoke.txt

# recon with longer waits + seed
.\RPM-Recon.annotated.ps1 -HostsPath .\csv\hosts_smoke.txt -MaxParallel 3 -MaxWaitSeconds 180 -SeedIfEmpty

# one-off enforce
.\Enforce-Mapping-SingleHost.ps1 -MaxWaitSeconds 180
