<#
.SYNOPSIS
    QR-friendly task dispatcher. One runner, many tasks.

.DESCRIPTION
    Central entry point for QR code payloads. Each QR encodes a short
    launch string that calls this script with a -Task name. The real
    logic lives in sibling scripts inside the QRTasks folder.

    Design principle: QR = pointer, not payload.
    Keep QR strings under ~120 characters. Never embed full scripts.

.PARAMETER Task
    The task to run. Use -Task ? or omit to list available tasks.

.PARAMETER ScriptRoot
    Override the folder that contains the task scripts.
    Defaults to the same directory as this dispatcher.

.EXAMPLE
    # QR payload (fits in a small QR code):
    powershell.exe -NoP -EP Bypass -File "\\server\Scripts\QRTasks\Invoke-TechTask.ps1" -Task RAMProfile

.EXAMPLE
    # List all available tasks:
    .\Invoke-TechTask.ps1 -Task ?

.NOTES
    Part of SysAdminSuite -- QRTasks extension module.
    See QRTasks\README-QRTasks.md for the full approach and QR catalog.
#>
param(
    [Parameter(Position = 0)]
    [string]$Task,

    [string]$ScriptRoot = '',

    [int]$TaskTimeoutSec = 180,

    [switch]$DisableTaskTimeout
)

if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
    $ScriptRoot = Split-Path -Parent $PSCommandPath
}

# ── Task registry ────────────────────────────────────────────────────
# Map short names to script filenames (relative to $ScriptRoot).
$TaskMap = [ordered]@{
    RAMProfile  = 'Get-RAMProfile.ps1'
    ModelInfo   = 'Get-ModelInfo.ps1'
    NetworkInfo = 'Get-NetworkInfo.ps1'
    Serials     = 'Get-Serials.ps1'
    NeuronTrace = 'Get-NeuronTrace.ps1'
}

# ── Help / list mode ────────────────────────────────────────────────
if (-not $Task -or $Task -eq '?') {
    Write-Host "`n  Available tasks:`n" -ForegroundColor Cyan
    foreach ($key in $TaskMap.Keys) {
        $path = Join-Path $ScriptRoot $TaskMap[$key]
        $exists = if (Test-Path -LiteralPath $path) { '' } else { ' [MISSING]' }
        Write-Host "    $key$exists" -ForegroundColor White
    }
    Write-Host "`n  Usage:" -ForegroundColor Cyan
    Write-Host '    powershell.exe -NoP -EP Bypass -File "<path>\Invoke-TechTask.ps1" -Task <TaskName>' -ForegroundColor Gray
    Write-Host ''
    return
}

# ── Resolve and run ─────────────────────────────────────────────────
if (-not $TaskMap.Contains($Task)) {
    Write-Warning "Unknown task: '$Task'. Run with -Task ? to see available tasks."
    return
}

$targetScript = Join-Path $ScriptRoot $TaskMap[$Task]

if (-not (Test-Path -LiteralPath $targetScript)) {
    Write-Warning "Task script not found: $targetScript"
    return
}

Write-Host "`n  Running task: $Task" -ForegroundColor Cyan
Write-Host "  Script:       $targetScript`n" -ForegroundColor DarkGray

if (-not $DisableTaskTimeout -and $TaskTimeoutSec -lt 5) {
    Write-Warning "TaskTimeoutSec must be >= 5. Using 5 seconds."
    $TaskTimeoutSec = 5
}

$script:CurrentTaskJob = $null
trap [System.Management.Automation.PipelineStoppedException] {
    if ($script:CurrentTaskJob -and $script:CurrentTaskJob.State -eq 'Running') {
        Stop-Job -Job $script:CurrentTaskJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $script:CurrentTaskJob -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Warning 'Task interrupted (Ctrl+C). Running probe job has been stopped.'
    break
}

if ($DisableTaskTimeout) {
    & $targetScript
    return
}

$script:CurrentTaskJob = Start-Job -ScriptBlock {
    param([string]$ScriptPath)
    & $ScriptPath
} -ArgumentList $targetScript

if (Wait-Job -Job $script:CurrentTaskJob -Timeout $TaskTimeoutSec) {
    Receive-Job -Job $script:CurrentTaskJob
    Remove-Job -Job $script:CurrentTaskJob -ErrorAction SilentlyContinue | Out-Null
} else {
    Stop-Job -Job $script:CurrentTaskJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $script:CurrentTaskJob -ErrorAction SilentlyContinue | Out-Null
    throw "Task '$Task' exceeded timeout ($TaskTimeoutSec s) and was force-stopped."
}

