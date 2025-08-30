<#
.SYNOPSIS
  Pushes a shortcut to the Public Desktop of remote PCs asynchronously.

.DESCRIPTION
  Reads hostnames from "hosts.txt" in the same folder.
  Only copies the shortcut if it does not already exist.
  Uses background jobs for asynchronous execution.

.PARAMETER ShortcutPath
  Path to the local shortcut you want to distribute.

.PARAMETER HostsFile
  Path to the file containing hostnames (default = hosts.txt in script dir).
#>

param(
    [string]$ShortcutPath = ".\Nuance Powershare.lnk",
    [string]$HostsFile = ".\hosts.txt"
)

if (-not (Test-Path $ShortcutPath)) {
    Write-Error "❌ Shortcut file not found: $ShortcutPath"
    exit 1
}

if (-not (Test-Path $HostsFile)) {
    Write-Error "❌ Hosts file not found: $HostsFile"
    exit 1
}

$hosts = Get-Content $HostsFile | Where-Object { $_ -and $_.Trim() -ne "" }

$jobs = @()

foreach ($host in $hosts) {
    $jobs += Start-Job -Name "Copy_$host" -ScriptBlock {
        param($host, $ShortcutPath)

        $destPath = "\\$host\C$\Users\Public\Desktop\$(Split-Path $ShortcutPath -Leaf)"

        try {
            if (Test-Path $destPath) {
                return "[$host] Skipped (already exists)"
            }
            Copy-Item -Path $ShortcutPath -Destination $destPath -Force -ErrorAction Stop
            return "[$host] Success"
        }
        catch {
            return "[$host] Failed: $($_.Exception.Message)"
        }
    } -ArgumentList $host, $ShortcutPath
}

Write-Host "⏳ Waiting for jobs to finish..."
Wait-Job $jobs | Out-Null

$results = Receive-Job $jobs
$results | ForEach-Object { Write-Host $_ }
Remove-Job $jobs
