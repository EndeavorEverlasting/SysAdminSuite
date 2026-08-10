[CmdletBinding()]
param(
    [switch]$SkipEvidence
)

$ErrorActionPreference = 'Stop'

$runRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-runs\clipboard'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $runRoot $timestamp
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

function Write-TextFile {
    param([string]$Path, [object]$Value)
    $Value | Out-String -Width 240 | Set-Content -Path $Path -Encoding UTF8
}

$summary = [ordered]@{
    Timestamp = (Get-Date).ToString('o')
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    Elevated = $false
    ClipboardService = @()
    ClipboardSequenceBefore = $null
    ClipboardOpenWindow = $null
    ClipboardOwnerPid = $null
    ClipboardOwnerProcess = $null
    ClipboardOwnerTitle = $null
    ServiceRestarted = $false
    ClipboardCleared = $false
    VerificationPassed = $false
    VerificationValue = $null
    EvidencePath = $runDir
}

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$summary.Elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$nativeSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SasClipboardNative {
    [DllImport("user32.dll")] public static extern IntPtr GetOpenClipboardWindow();
    [DllImport("user32.dll")] public static extern UInt32 GetClipboardSequenceNumber();
    [DllImport("user32.dll")] public static extern UInt32 GetWindowThreadProcessId(IntPtr hWnd, out UInt32 lpdwProcessId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
}
'@
Add-Type -TypeDefinition $nativeSource -ErrorAction SilentlyContinue

try {
    $summary.ClipboardSequenceBefore = [SasClipboardNative]::GetClipboardSequenceNumber()
    $hwnd = [SasClipboardNative]::GetOpenClipboardWindow()
    if ($hwnd -ne [IntPtr]::Zero) {
        $summary.ClipboardOpenWindow = ('0x{0:X}' -f $hwnd.ToInt64())
        [uint32]$pid = 0
        [void][SasClipboardNative]::GetWindowThreadProcessId($hwnd, [ref]$pid)
        if ($pid -gt 0) {
            $summary.ClipboardOwnerPid = [int]$pid
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc) {
                $summary.ClipboardOwnerProcess = $proc.ProcessName
            }
        }
        $title = New-Object System.Text.StringBuilder 512
        [void][SasClipboardNative]::GetWindowText($hwnd, $title, $title.Capacity)
        $summary.ClipboardOwnerTitle = $title.ToString()
    }
} catch {
    $summary.ClipboardProbeError = $_.Exception.Message
}

$services = @(Get-Service -Name 'cbdhsvc*' -ErrorAction SilentlyContinue)
$summary.ClipboardService = @($services | Select-Object Name, Status, StartType)

if (-not $SkipEvidence) {
    Write-TextFile -Path (Join-Path $runDir 'services-before.txt') -Value $services
    Write-TextFile -Path (Join-Path $runDir 'processes-before.txt') -Value (Get-Process | Where-Object { $_.ProcessName -match '^(explorer|rdpclip|TextInputHost|msedge|chrome|firefox|pwsh|powershell)$' } | Select-Object ProcessName, Id, MainWindowTitle)
}

try {
    if ($services) {
        $services | Restart-Service -Force -ErrorAction Stop
        $summary.ServiceRestarted = $true
    }
} catch {
    $summary.ServiceRestartError = $_.Exception.Message
}

try {
    Set-Clipboard -Value $null
    $summary.ClipboardCleared = $true
} catch {
    $summary.ClipboardClearError = $_.Exception.Message
}

try {
    $probe = 'SAS_CLIPBOARD_TEST_{0}' -f (Get-Date -Format 'yyyyMMddHHmmssfff')
    Set-Clipboard -Value $probe
    Start-Sleep -Milliseconds 150
    $readBack = Get-Clipboard -Raw -ErrorAction Stop
    $summary.VerificationValue = $readBack
    $summary.VerificationPassed = ($readBack -eq $probe)
    if ($summary.VerificationPassed) {
        Set-Clipboard -Value $null
    }
} catch {
    $summary.VerificationError = $_.Exception.Message
}

$summary | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $runDir 'summary.json') -Encoding UTF8

Write-Host ''
Write-Host '============================================================'
Write-Host ' SysAdminSuite Clipboard Recovery'
Write-Host '============================================================'
if ($summary.ClipboardOpenWindow) {
    Write-Host ('Clipboard holder before reset: HWND {0}  PID {1}  Process {2}' -f $summary.ClipboardOpenWindow, $summary.ClipboardOwnerPid, $summary.ClipboardOwnerProcess)
} else {
    Write-Host 'Clipboard holder before reset: none detected'
}
Write-Host ('Clipboard service restart: {0}' -f $(if ($summary.ServiceRestarted) { 'PASS' } else { 'NOT CONFIRMED' }))
Write-Host ('Clipboard round-trip test: {0}' -f $(if ($summary.VerificationPassed) { 'PASS' } else { 'FAIL' }))
Write-Host ('Evidence: {0}' -f $runDir)
Write-Host '============================================================'

if ($summary.VerificationPassed) { exit 0 }
exit 1
