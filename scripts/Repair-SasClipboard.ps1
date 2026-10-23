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

function Test-CurrentWindowsIdentity {
    param(
        [string]$Candidate,
        [string]$CurrentIdentity,
        [string]$CurrentUserName
    )

    if (-not $Candidate) {
        return $false
    }

    if ($Candidate.Equals($CurrentIdentity, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    if ($Candidate.StartsWith('.\') -and
        $Candidate.Substring(2).Equals($CurrentUserName, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $false
}

function Get-ServiceProcessOwnerIdentity {
    param([object]$ServiceRow)

    if ([int]$ServiceRow.ProcessId -le 0) {
        return $null
    }

    try {
        $processRow = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f [int]$ServiceRow.ProcessId) -ErrorAction Stop
        $owner = Invoke-CimMethod -InputObject $processRow -MethodName GetOwner -ErrorAction Stop
        if ($owner.ReturnValue -eq 0 -and $owner.User) {
            if ($owner.Domain) {
                return '{0}\{1}' -f $owner.Domain, $owner.User
            }
            return [string]$owner.User
        }
    } catch {
        return $null
    }

    return $null
}

function Get-CurrentUserClipboardService {
    param(
        [string]$CurrentIdentity,
        [string]$CurrentUserName
    )

    $rows = @(Get-CimInstance Win32_Service -Filter "Name LIKE 'cbdhsvc_%'" -ErrorAction Stop)
    $matches = New-Object System.Collections.Generic.List[object]

    foreach ($row in $rows) {
        $matched = Test-CurrentWindowsIdentity -Candidate ([string]$row.StartName) -CurrentIdentity $CurrentIdentity -CurrentUserName $CurrentUserName
        if (-not $matched) {
            $processOwner = Get-ServiceProcessOwnerIdentity -ServiceRow $row
            $matched = Test-CurrentWindowsIdentity -Candidate $processOwner -CurrentIdentity $CurrentIdentity -CurrentUserName $CurrentUserName
        }
        if ($matched) {
            $matches.Add($row)
        }
    }

    if ($matches.Count -ne 1) {
        return [pscustomobject]@{
            Service = $null
            Rows = $rows
            Error = 'Expected exactly one cbdhsvc_* instance owned by {0}; found {1}.' -f $CurrentIdentity, $matches.Count
        }
    }

    return [pscustomobject]@{
        Service = Get-Service -Name $matches[0].Name -ErrorAction Stop
        Rows = $rows
        Error = $null
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentIdentity = $identity.Name
$principal = [Security.Principal.WindowsPrincipal]$identity

$summary = [ordered]@{
    Timestamp = (Get-Date).ToString('o')
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    Identity = $currentIdentity
    Elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    ClipboardService = @()
    SelectedClipboardService = $null
    ClipboardSequenceBefore = $null
    ClipboardOpenWindow = $null
    ClipboardOwnerPid = $null
    ClipboardOwnerProcess = $null
    ClipboardOwnerTitle = $null
    ServiceRestarted = $false
    ClipboardCleared = $false
    VerificationPassed = $false
    VerificationValue = $null
    RecoveryPassed = $false
    EvidencePath = $runDir
}

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

$exitCode = 1

try {
    Add-Type -TypeDefinition $nativeSource -ErrorAction SilentlyContinue

    try {
        $summary.ClipboardSequenceBefore = [SasClipboardNative]::GetClipboardSequenceNumber()
        $hwnd = [SasClipboardNative]::GetOpenClipboardWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            $summary.ClipboardOpenWindow = ('0x{0:X}' -f $hwnd.ToInt64())
            [uint32]$ownerPid = 0
            [void][SasClipboardNative]::GetWindowThreadProcessId($hwnd, [ref]$ownerPid)
            if ($ownerPid -gt 0) {
                $summary.ClipboardOwnerPid = [int]$ownerPid
                $proc = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
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

    try {
        $selection = Get-CurrentUserClipboardService -CurrentIdentity $currentIdentity -CurrentUserName $env:USERNAME
        $summary.ClipboardService = @($selection.Rows | Select-Object Name, State, StartMode, StartName, ProcessId)
        if ($selection.Error) {
            $summary.ServiceSelectionError = $selection.Error
        } else {
            $service = $selection.Service
            $summary.SelectedClipboardService = $service.Name
        }
    } catch {
        $summary.ServiceSelectionError = $_.Exception.Message
        $service = $null
    }

    if (-not $SkipEvidence) {
        try {
            Write-TextFile -Path (Join-Path $runDir 'services-before.txt') -Value $summary.ClipboardService
        } catch {
            $summary.ServiceEvidenceError = $_.Exception.Message
        }

        try {
            $interestingProcesses = Get-Process -ErrorAction Stop |
                Where-Object { $_.ProcessName -match '^(explorer|rdpclip|TextInputHost|msedge|chrome|firefox|pwsh|powershell)$' } |
                Select-Object ProcessName, Id, MainWindowTitle
            Write-TextFile -Path (Join-Path $runDir 'processes-before.txt') -Value $interestingProcesses
        } catch {
            $summary.ProcessEvidenceError = $_.Exception.Message
        }
    }

    if ($service) {
        try {
            Restart-Service -InputObject $service -Force -ErrorAction Stop
            $summary.ServiceRestarted = $true
        } catch {
            $summary.ServiceRestartError = $_.Exception.Message
        }
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

    $summary.RecoveryPassed = (
        $summary.SelectedClipboardService -and
        $summary.ServiceRestarted -and
        $summary.ClipboardCleared -and
        $summary.VerificationPassed
    )

    if ($summary.RecoveryPassed) {
        $exitCode = 0
    }
} catch {
    $summary.UnhandledError = $_.Exception.Message
    $exitCode = 1
} finally {
    try {
        $summary | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $runDir 'summary.json') -Encoding UTF8
    } catch {
        Write-Warning ('Unable to persist clipboard recovery summary: {0}' -f $_.Exception.Message)
        $exitCode = 1
    }
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' SysAdminSuite Clipboard Recovery'
Write-Host '============================================================'
if ($summary.ClipboardOpenWindow) {
    Write-Host ('Clipboard holder before reset: HWND {0}  PID {1}  Process {2}' -f $summary.ClipboardOpenWindow, $summary.ClipboardOwnerPid, $summary.ClipboardOwnerProcess)
} else {
    Write-Host 'Clipboard holder before reset: none detected'
}
Write-Host ('Selected clipboard service: {0}' -f $(if ($summary.SelectedClipboardService) { $summary.SelectedClipboardService } else { 'NOT RESOLVED' }))
Write-Host ('Clipboard service restart: {0}' -f $(if ($summary.ServiceRestarted) { 'PASS' } else { 'FAIL' }))
Write-Host ('Clipboard clear: {0}' -f $(if ($summary.ClipboardCleared) { 'PASS' } else { 'FAIL' }))
Write-Host ('Clipboard round-trip test: {0}' -f $(if ($summary.VerificationPassed) { 'PASS' } else { 'FAIL' }))
Write-Host ('Evidence: {0}' -f $runDir)
Write-Host '============================================================'

exit $exitCode
