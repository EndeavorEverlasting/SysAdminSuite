#Requires -Version 5.1
<#
.SYNOPSIS
  Discover and close Chrome crash-recovery ghost browser sessions on this controller.

.NOTES
  Remediation is process-tree termination only (taskkill /T /F on classified ghost roots).
  Muting, volume clamps, and mixer band-aids are forbidden: they pretend the session is fixed
  while audio can keep playing or resume later. Closing the ghost root is the fix.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Json
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    Write-Error 'Chrome ghost-session close is supported on Windows only.'
    exit 2
}

function Get-SasChromeBrowserRoots {
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'chrome.exe'" -ErrorAction Stop)
    @(
        $processes |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
                [string]$_.CommandLine -notmatch '(?i)--type='
            } |
            ForEach-Object {
                $created = $null
                if ($_.CreationDate -is [datetime]) {
                    $created = [datetime]$_.CreationDate
                }
                elseif (-not [string]::IsNullOrWhiteSpace([string]$_.CreationDate)) {
                    try {
                        $created = [datetime]$_.CreationDate
                    }
                    catch {
                        $created = $null
                    }
                }
                [pscustomobject][ordered]@{
                    pid = [int]$_.ProcessId
                    parent_pid = [int]$_.ParentProcessId
                    command_line = [string]$_.CommandLine
                    creation_date = $created
                }
            }
    )
}

function Get-SasChromeProcessTreeMap {
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'chrome.exe'" -ErrorAction Stop)
    $byParent = @{}
    foreach ($process in $processes) {
        $parentId = [int]$process.ParentProcessId
        if (-not $byParent.ContainsKey($parentId)) {
            $byParent[$parentId] = @()
        }
        $byParent[$parentId] += $process
    }
    return @{
        All = $processes
        ByParent = $byParent
    }
}

function Get-SasChromeDescendants {
    param(
        [Parameter(Mandatory = $true)][int]$RootPid,
        [Parameter(Mandatory = $true)][hashtable]$TreeMap
    )

    $ordered = @()
    $queue = [System.Collections.ArrayList]@([int]$RootPid)
    $seen = @{ [int]$RootPid = $true }

    while ($queue.Count -gt 0) {
        $current = [int]$queue[0]
        $queue.RemoveAt(0) | Out-Null
        if (-not $TreeMap.ByParent.ContainsKey($current)) { continue }
        foreach ($child in @($TreeMap.ByParent[$current])) {
            $childPid = [int]$child.ProcessId
            if ($seen.ContainsKey($childPid)) { continue }
            $seen[$childPid] = $true
            $ordered += $child
            [void]$queue.Add($childPid)
        }
    }

    return @($ordered)
}

function Get-SasChromeVisibleBrowserWindows {
    param(
        [Parameter(Mandatory = $true)][int[]]$ProcessIds
    )

    if ($ProcessIds.Count -eq 0) { return @() }

    if (-not ('SasChromeWinEnum' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class SasChromeWinEnum {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);

    public static List<string> Collect(HashSet<int> processIds) {
        var rows = new List<string>();
        EnumWindows((hWnd, lParam) => {
            uint ownerPid = 0;
            GetWindowThreadProcessId(hWnd, out ownerPid);
            if (!processIds.Contains((int)ownerPid)) { return true; }
            var className = new StringBuilder(256);
            GetClassName(hWnd, className, className.Capacity);
            string cls = className.ToString();
            if (cls != "Chrome_WidgetWin_1") { return true; }
            if (!IsWindowVisible(hWnd)) { return true; }
            int length = GetWindowTextLength(hWnd);
            var title = new StringBuilder(length + 1);
            GetWindowText(hWnd, title, title.Capacity);
            string text = title.ToString();
            if (string.IsNullOrWhiteSpace(text)) { return true; }
            rows.Add(((long)hWnd).ToString() + "|" + ownerPid.ToString() + "|" + (IsIconic(hWnd) ? "1" : "0") + "|" + text);
            return true;
        }, IntPtr.Zero);
        return rows;
    }
}
"@
    }

    $idSet = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($processId in $ProcessIds) { [void]$idSet.Add([int]$processId) }
    $raw = @([SasChromeWinEnum]::Collect($idSet))
    @(
        $raw | ForEach-Object {
            $parts = ([string]$_) -split '\|', 4
            [pscustomobject][ordered]@{
                hwnd = [int64]$parts[0]
                pid = [int]$parts[1]
                iconic = ($parts[2] -eq '1')
                title = $parts[3]
            }
        }
    )
}

function Test-SasParentProcessAlive {
    param([Parameter(Mandatory = $true)][int]$ParentPid)
    if ($ParentPid -le 0) { return $false }
    return [bool](Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)
}

$treeMap = Get-SasChromeProcessTreeMap
$roots = @(Get-SasChromeBrowserRoots)
$ghosts = @()
$healthy = @()

foreach ($root in $roots) {
    $descendants = @(Get-SasChromeDescendants -RootPid $root.pid -TreeMap $treeMap)
    $treePids = @($root.pid) + @($descendants | ForEach-Object { [int]$_.ProcessId })
    $visibleWindows = @(Get-SasChromeVisibleBrowserWindows -ProcessIds $treePids)
    $audioChildren = @(
        $descendants |
            Where-Object { [string]$_.CommandLine -match '(?i)audio\.mojom\.AudioService' }
    )
    $rendererChildren = @(
        $descendants |
            Where-Object { [string]$_.CommandLine -match '(?i)--type=renderer' }
    )
    $isRestart = [string]$root.command_line -match '(?i)(^|\s)--restart(\s|$)'
    $isHeadless = [string]$root.command_line -match '(?i)--headless'
    $parentAlive = Test-SasParentProcessAlive -ParentPid $root.parent_pid
    $reasons = @()
    if ($isRestart) { $reasons += 'restart_flag' }
    if (-not $parentAlive) { $reasons += 'parent_process_missing' }
    if ($visibleWindows.Count -eq 0) { $reasons += 'no_visible_chrome_widget_window' }
    if ($audioChildren.Count -gt 0) { $reasons += 'audio_service_present' }
    if ($rendererChildren.Count -gt 0 -and $visibleWindows.Count -eq 0) {
        $reasons += 'renderers_without_visible_ui'
    }

    $classification = 'HEALTHY_OR_UNKNOWN'
    if ($isHeadless) {
        $classification = 'HEADLESS_EXCLUDED'
    }
    elseif (
        $visibleWindows.Count -eq 0 -and (
            $isRestart -or
            (
                -not $parentAlive -and
                $audioChildren.Count -gt 0 -and
                $rendererChildren.Count -gt 0
            )
        )
    ) {
        # Ghost = no visible Chrome_WidgetWin_1 UI, plus crash-restart (--restart)
        # or an orphaned audio+renderer tree. Intentional background Chrome without
        # --restart and with a live parent stays HEALTHY_OR_UNKNOWN.
        $classification = 'CHROME_GHOST_SESSION'
    }

    $record = [pscustomobject][ordered]@{
        classification = $classification
        root_pid = $root.pid
        parent_pid = $root.parent_pid
        parent_alive = $parentAlive
        command_line = $root.command_line
        creation_date = if ($null -ne $root.creation_date) { $root.creation_date.ToString('o') } else { $null }
        tree_process_count = $treePids.Count
        visible_browser_window_count = $visibleWindows.Count
        audio_service_pids = @($audioChildren | ForEach-Object { [int]$_.ProcessId })
        renderer_count = $rendererChildren.Count
        reasons = @($reasons)
        visible_windows = @($visibleWindows)
    }

    if ($classification -eq 'CHROME_GHOST_SESSION') {
        $ghosts += $record
    }
    else {
        $healthy += $record
    }
}

$closed = @()
$errors = @()

if ($Apply -and $ghosts.Count -gt 0) {
    foreach ($ghost in $ghosts) {
        $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
        $killArgs = @('/PID', ([string]$ghost.root_pid), '/T', '/F')
        $output = & $taskkill @killArgs 2>&1
        $exitCode = $LASTEXITCODE
        $stillPresent = [bool](Get-Process -Id $ghost.root_pid -ErrorAction SilentlyContinue)
        $closed += [pscustomobject][ordered]@{
            root_pid = $ghost.root_pid
            taskkill_exit_code = $exitCode
            still_present = $stillPresent
            output = @($output | ForEach-Object { [string]$_ })
        }
        if ($exitCode -ne 0 -or $stillPresent) {
            $errors += "Failed to close Chrome ghost root PID $($ghost.root_pid)"
        }
    }
}

function Get-SasChromeCrashSessionForensics {
    $userData = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
    $preferencesPath = Join-Path $userData 'Default\Preferences'
    $exitType = $null
    $exitedCleanly = $null
    if (Test-Path -LiteralPath $preferencesPath -PathType Leaf) {
        try {
            $prefs = Get-Content -LiteralPath $preferencesPath -Raw -ErrorAction Stop
            $exitMatch = [regex]::Match($prefs, '"exit_type"\s*:\s*"([^"]+)"')
            if ($exitMatch.Success) { $exitType = $exitMatch.Groups[1].Value }
            $cleanMatch = [regex]::Match($prefs, '"exited_cleanly"\s*:\s*(true|false)')
            if ($cleanMatch.Success) { $exitedCleanly = [bool]::Parse($cleanMatch.Groups[1].Value) }
        }
        catch {
            # Preferences can be locked or mid-write; forensics stay best-effort.
        }
    }

    $youtubeIds = @()
    $sessionsDir = Join-Path $userData 'Default\Sessions'
    if (Test-Path -LiteralPath $sessionsDir -PathType Container) {
        $tabFiles = @(
            Get-ChildItem -LiteralPath $sessionsDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'Tabs_*' } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 2
        )
        foreach ($tabFile in $tabFiles) {
            try {
                $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($tabFile.FullName))
                $youtubeIds += @(
                    [regex]::Matches($ascii, 'youtube\.com/watch\?v=([\w-]{11})') |
                        ForEach-Object { $_.Groups[1].Value }
                )
            }
            catch {
                # Ignore unreadable tab snapshots.
            }
        }
    }

    $uniqueIds = @($youtubeIds | Select-Object -Unique | Select-Object -First 12)
    return [pscustomobject][ordered]@{
        preferences_exit_type = $exitType
        preferences_exited_cleanly = $exitedCleanly
        crashed_or_unclean_exit = (
            ($exitType -eq 'Crashed') -or
            ($null -ne $exitedCleanly -and -not $exitedCleanly)
        )
        recent_youtube_video_ids = $uniqueIds
        note = 'Tab-group close glitches often leave exit_type=Crashed plus YouTube IDs in Tabs_* even after chrome.exe is gone.'
    }
}

$crashForensics = Get-SasChromeCrashSessionForensics

$mode = 'DISCOVER'
if ($Apply) { $mode = 'APPLY' }

$outcome = 'CHROME_GHOST_NONE'
if ($errors.Count -gt 0) {
    $outcome = 'CHROME_GHOST_CLOSE_FAILED'
}
elseif ($Apply -and $ghosts.Count -gt 0) {
    $outcome = 'CHROME_GHOST_CLOSED'
}
elseif ($ghosts.Count -gt 0) {
    $outcome = 'CHROME_GHOST_DETECTED'
}
elseif ($crashForensics.crashed_or_unclean_exit -and $roots.Count -eq 0) {
    $outcome = 'CHROME_PROCESS_GONE_CRASH_SESSION_RESIDUE'
}

$result = [pscustomobject][ordered]@{
    schema_version = 'sas-chrome-ghost-session/v1'
    mode = $mode
    remediation = 'process_tree_terminate_only'
    mute_or_volume_clamp_allowed = $false
    chrome_browser_root_count = $roots.Count
    ghost_session_count = $ghosts.Count
    healthy_or_excluded_count = $healthy.Count
    ghosts = @($ghosts)
    healthy_or_excluded = @($healthy)
    closed = @($closed)
    crash_session_forensics = $crashForensics
    network_activity_performed = $false
    target_contact_performed = $false
    target_mutation_performed = $false
    local_process_mutation_performed = [bool]($Apply -and $closed.Count -gt 0)
    outcome = $outcome
    errors = @($errors)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-Host ("MODE: {0}" -f $result.mode) -ForegroundColor Cyan
    Write-Host ("OUTCOME: {0}" -f $result.outcome) -ForegroundColor $(if ($result.outcome -eq 'CHROME_GHOST_CLOSE_FAILED') { 'Red' } elseif ($result.ghost_session_count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host ("Chrome browser roots: {0}; ghost sessions: {1}" -f $result.chrome_browser_root_count, $result.ghost_session_count)
    foreach ($ghost in $ghosts) {
        Write-Host ("GHOST root_pid={0} parent_pid={1} parent_alive={2} audio_pids=[{3}] reasons=[{4}]" -f `
            $ghost.root_pid,
            $ghost.parent_pid,
            $ghost.parent_alive,
            ($ghost.audio_service_pids -join ','),
            ($ghost.reasons -join ',')) -ForegroundColor Yellow
        Write-Host ("  cmdline: {0}" -f $ghost.command_line)
    }
    if ($Apply) {
        foreach ($item in $closed) {
            Write-Host ("CLOSED root_pid={0} taskkill_exit={1} still_present={2}" -f $item.root_pid, $item.taskkill_exit_code, $item.still_present)
        }
    }
    elseif ($ghosts.Count -gt 0) {
        Write-Host 'Dry-run only. Re-run with -Apply (or Close-ChromeGhostSession.cmd apply) to terminate classified ghost roots.' -ForegroundColor DarkGray
    }
    if ($null -ne $crashForensics.preferences_exit_type -or $crashForensics.recent_youtube_video_ids.Count -gt 0) {
        Write-Host ("CRASH_FORENSICS exit_type={0} exited_cleanly={1} youtube_ids=[{2}]" -f `
            $crashForensics.preferences_exit_type,
            $crashForensics.preferences_exited_cleanly,
            ($crashForensics.recent_youtube_video_ids -join ',')) -ForegroundColor DarkYellow
    }
    if ($result.outcome -eq 'CHROME_PROCESS_GONE_CRASH_SESSION_RESIDUE') {
        Write-Host 'No chrome.exe remains. Crash/tab-group residue is in Chrome session files only; if audio continues, check the same Bluetooth headset on a phone or another device.' -ForegroundColor DarkYellow
    }
}

if ($result.outcome -eq 'CHROME_GHOST_CLOSE_FAILED') { exit 1 }
if ($result.outcome -eq 'CHROME_GHOST_DETECTED' -and -not $Apply) { exit 3 }
if ($result.outcome -eq 'CHROME_PROCESS_GONE_CRASH_SESSION_RESIDUE') { exit 4 }
exit 0
