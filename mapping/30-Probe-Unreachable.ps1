#requires -version 5.1
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$csvDir = Join-Path $root 'csv'
$path   = Join-Path $csvDir 'hosts_unreachable.txt'
if (!(Test-Path $path)) { throw "Missing: $path (run 00-Build-HostSets.ps1 first)" }

$targets = Get-Content -LiteralPath $path | ? { $_ }
$probe = foreach($h in $targets){
  $fqdn = try{ [System.Net.Dns]::GetHostEntry($h).HostName } catch { $null }
  $ip   = try{ (Resolve-DnsName ($fqdn ?? $h) -Type A -EA Stop).IPAddress[0] } catch { $null }
  [pscustomobject]@{
    Host   = $h
    FQDN   = $fqdn
    IP     = $ip
    Ping   = if($ip){ Test-Connection -Count 1 -Quiet $ip } else { $false }
    ADMIN$ = @("\\$h\ADMIN$", if($fqdn){"\\$fqdn\ADMIN$"}, if($ip){"\\$ip\ADMIN$"}) |
             ? { $_ } | % { [bool](Test-Path $_) } | Select-Object -First 1
    Likely = if(-not $fqdn){'DNS'} elseif(-not $ip){'A-record'} elseif(-not $PSItem.ADMIN$){'SMB/Admin'} else {'Other'}
  }
}
$out = Join-Path $csvDir 'hosts_unreachable_triage.csv'
$probe | Export-Csv -NoTypeInformation -LiteralPath $out
"➡  Wrote: $out"
