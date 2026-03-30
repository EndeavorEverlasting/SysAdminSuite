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
    # Run locally from the repo:
    .\QRTasks\Invoke-TechTask.ps1 -Task RAMProfile

.EXAMPLE
    # QR payload pointing to a central share (replace <YOUR-HOST> with your file server):
    powershell.exe -NoP -EP Bypass -File "\\<YOUR-HOST>\c$\Scripts\QRTasks\Invoke-TechTask.ps1" -Task RAMProfile

.EXAMPLE
    # List all available tasks:
    .\Invoke-TechTask.ps1 -Task ?

.NOTES
    Part of SysAdminSuite — QRTasks extension module.

    QR design principle: QR = pointer, not payload.
    The QR code encodes a short launch string (~100 chars).
    The real scripts live here or on a central share.
#>
param(
    [Parameter(Position = 0)]
    [string]$Task,

    [string]$ScriptRoot = $PSScriptRoot,

    [string]$LocalFallback = (Join-Path $env:COMPUTERNAME 'c$\Scripts\QRTasks')
)

# ── Task registry ────────────────────────────────────────────────────
# Map short names to script filenames (relative to $ScriptRoot).
$TaskMap = [ordered]@{
    RAMProfile  = 'Get-RAMProfile.ps1'
    ModelInfo   = 'Get-ModelInfo.ps1'
    NetworkInfo = 'Get-NetworkInfo.ps1'
    Serials     = 'Get-Serials.ps1'
}

# ── Resolve script root with localhost fallback ──────────────────────
# If the network ScriptRoot is unreachable (share down, VPN off, etc.)
# fall back to: \\localhost\c$\Scripts\QRTasks, then $PSScriptRoot.
function Resolve-ScriptRoot {
    param([string]$Primary, [string]$Fallback)

    if ($Primary -and (Test-Path -LiteralPath $Primary -ErrorAction SilentlyContinue)) {
        return $Primary
    }

    if ($Primary -and $Primary -ne $PSScriptRoot) {
        Write-Warning "Network path unreachable: $Primary"
    }

    # Try localhost UNC — works even when the original share host is down
    $localhostPath = "\\localhost\c`$\Scripts\QRTasks"
    if (Test-Path -LiteralPath $localhostPath -ErrorAction SilentlyContinue) {
        Write-Host "  Falling back to localhost: $localhostPath" -ForegroundColor Yellow
        return $localhostPath
    }

    # Try \\<COMPUTERNAME>\c$\Scripts\QRTasks
    $compPath = "\\$env:COMPUTERNAME\c`$\Scripts\QRTasks"
    if ($compPath -ne $localhostPath -and (Test-Path -LiteralPath $compPath -ErrorAction SilentlyContinue)) {
        Write-Host "  Falling back to local host: $compPath" -ForegroundColor Yellow
        return $compPath
    }

    # Last resort: the directory this script lives in
    if ($PSScriptRoot -and (Test-Path -LiteralPath $PSScriptRoot -ErrorAction SilentlyContinue)) {
        Write-Host "  Falling back to script directory: $PSScriptRoot" -ForegroundColor Yellow
        return $PSScriptRoot
    }

    return $Primary  # let it fail with a clear error downstream
}

$ScriptRoot = Resolve-ScriptRoot -Primary $ScriptRoot -Fallback $LocalFallback

# ── Help / list mode ────────────────────────────────────────────────
if (-not $Task -or $Task -eq '?') {
    Write-Host "`n  Available tasks:`n" -ForegroundColor Cyan
    Write-Host "  Script root: $ScriptRoot`n" -ForegroundColor DarkGray
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

& $targetScript

