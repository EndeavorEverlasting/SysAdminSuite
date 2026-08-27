[CmdletBinding()]
param(
    [ValidateRange(5, 3600)]
    [int]$Seconds = 90,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$processNames = @('dism', 'dismhost', 'TiWorker', 'TrustedInstaller')
$logPaths = @('C:\Windows\Logs\DISM\dism.log', 'C:\Windows\Logs\CBS\CBS.log')

function Get-Snapshot {
    $processes = @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -in $processNames } |
        ForEach-Object {
            [pscustomobject]@{ name = $_.ProcessName; pid = $_.Id; cpu_seconds = $_.CPU; working_set_bytes = [int64]$_.WorkingSet64 }
        })
    $logs = @($logPaths | ForEach-Object {
        if (Test-Path -LiteralPath $_ -PathType Leaf) {
            $item = Get-Item -LiteralPath $_
            [pscustomobject]@{ path = $_; bytes = [int64]$item.Length; last_write_utc = $item.LastWriteTimeUtc.ToString('o') }
        }
    })
    [pscustomobject]@{ processes = $processes; logs = $logs }
}

$before = Get-Snapshot
Start-Sleep -Seconds $Seconds
$after = Get-Snapshot

$processDelta = @($after.processes | ForEach-Object {
    $current = $_
    $old = $before.processes | Where-Object { $_.pid -eq $current.pid } | Select-Object -First 1
    [pscustomobject]@{
        name = $current.name
        pid = $current.pid
        cpu_delta_seconds = if ($old -and $null -ne $current.cpu_seconds -and $null -ne $old.cpu_seconds) { [double]$current.cpu_seconds - [double]$old.cpu_seconds } else { $null }
        working_set_bytes = $current.working_set_bytes
    }
})

$logDelta = @($after.logs | ForEach-Object {
    $current = $_
    $old = $before.logs | Where-Object { $_.path -eq $current.path } | Select-Object -First 1
    [pscustomobject]@{
        path = $current.path
        bytes_added = if ($old) { [int64]$current.bytes - [int64]$old.bytes } else { $null }
        before_last_write_utc = if ($old) { $old.last_write_utc } else { $null }
        after_last_write_utc = $current.last_write_utc
    }
})

$cpuMoved = @($processDelta | Where-Object { $null -ne $_.cpu_delta_seconds -and $_.cpu_delta_seconds -gt 0.05 }).Count -gt 0
$logMoved = @($logDelta | Where-Object { $null -ne $_.bytes_added -and $_.bytes_added -gt 0 }).Count -gt 0
$activity = $cpuMoved -or $logMoved

$result = [pscustomobject]@{
    schema_version = '1.0'
    sample_seconds = $Seconds
    activity_observed = $activity
    processes = $processDelta
    logs = $logDelta
    interpretation = if ($activity) {
        'Servicing activity was observed during the sample; a static percentage is not a reason to terminate DISM.'
    } else {
        'No activity was observed during this sample. This is not proof of a dead process; combine it with prolonged stagnation and logs before a graceful Ctrl+C decision.'
    }
    safety = 'Read-only sampler. It never stops DISM, DISMHost, TiWorker, or TrustedInstaller.'
}

$json = $result | ConvertTo-Json -Depth 8
if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
}
$json
