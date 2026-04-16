# Run in an elevated PowerShell
$prefix = 'WNY075EPT'
$range  = 0..999 | ForEach-Object { '{0}{1:D3}' -f $prefix, $_ }

$alive  = foreach ($n in $range) {
  if (Resolve-DnsName -Name $n -ErrorAction SilentlyContinue) {
    if (Test-Connection -ComputerName $n -Count 1 -Quiet -ErrorAction SilentlyContinue) { $n }
  }
}

$hostListPath = 'C:\Temp\hostlist.txt'
New-Item -ItemType Directory -Path (Split-Path $hostListPath) -Force | Out-Null
$alive | Sort-Object -Unique | Out-File -FilePath $hostListPath -Encoding ascii
Get-Content $hostListPath | Measure-Object | ForEach-Object { "Hosts in scope: $($_.Count)" }
