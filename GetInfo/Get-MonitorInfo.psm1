function Get-NativeResolution {
    param([Parameter(Mandatory)][string]$InstanceName)

    $escapedInstance = $InstanceName -replace '\\','\\\\' -replace "'","''"
    try {
        $raw = (Get-CimInstance -Namespace root\wmi -Class WmiMonitorDescriptorMethods `
                -Filter "InstanceName='$escapedInstance'" -ErrorAction Stop).GetMonitorDescriptor(0,0).Descriptor

        if ($raw.Count -lt 18) { return "Unknown" }

        $h = $raw[2] + ((($raw[4] -shr 4) -band 0xF) * 256)
        $v = $raw[5] + ((($raw[7] -shr 4) -band 0xF) * 256)

        if ($h -gt 0 -and $v -gt 0) {
            return "$h`x$v"
        } else { return "Unknown" }
    }
    catch { return "Unknown" }
}

function Get-ConnectionType {
    param([Parameter(Mandatory)][string]$InstanceName)

    $techMap = @{
        '-2'='UNINITIALIZED'; '-1'='OTHER'; '0'='VGA'; '1'='S-VIDEO'; '2'='COMPOSITE';
        '3'='COMPONENT'; '4'='DVI'; '5'='HDMI'; '10'='DISPLAYPORT'; '11'='DP (embedded)';
        '13'='eDP'; '16'='USB-C/Alt-DP'; '2147483648'='INTERNAL'
    }

    try {
        $conn = Get-CimInstance -Namespace root\wmi -Class WmiMonitorConnectionParams |
                Where-Object { $_.InstanceName -eq $InstanceName }

        if (-not $conn) { return "UNKNOWN" }

        $code = [string]$conn.VideoOutputTechnology
        $tech = $techMap[$code]
        if (-not $tech) { return "UNKNOWN" }

        if ($tech -eq 'DISPLAYPORT') {
            try {
                $escapedDeviceId = $InstanceName -replace '\\','\\\\' -replace "'","''"
                $locationInfo = (Get-CimInstance Win32_PnPEntity `
                               -Filter "DeviceID='$escapedDeviceId'" -ErrorAction Stop).LocationInformation
                if ($locationInfo -match 'USB|TYPEC|TBT') { return 'USB-C (DP-Alt)' }
            } catch {
                Write-Verbose ("Failed PnPEntity lookup for '{0}': {1}" -f $InstanceName, $_.Exception.Message)
            }
        }
        return $tech
    }
    catch { return "UNKNOWN" }
}

function Get-DisplayDeviceMap {
    <#
    .SYNOPSIS
        Builds a mapping from monitor hardware-ID segments to Windows display numbers,
        screen bounds, and primary status using QueryDisplayConfig + Screen class.
    .DESCRIPTION
        Uses the Win32 QueryDisplayConfig / DisplayConfigGetDeviceInfo APIs to resolve
        each active display path.  The returned device-path contains the PnP hardware-ID
        segment (e.g. TSB0206, LEN60C7) that can be matched against WmiMonitorID
        InstanceName values.  Falls back gracefully if the API is unavailable.
    #>
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

    # ---- inline C# for QueryDisplayConfig (works in non-interactive sessions) ----
    $typeName = 'SysAdminSuite.DisplayConfigHelper'
    if (-not ([System.Management.Automation.PSTypeName]$typeName).Type) {
        $csCode = @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
namespace SysAdminSuite {
    public class DisplayConfigHelper {
        [Flags] enum QDC : uint { OnlyActivePaths = 2 }
        [StructLayout(LayoutKind.Sequential)] struct LUID { public uint LowPart; public int HighPart; }
        [StructLayout(LayoutKind.Sequential)] struct PATH_SRC { public LUID adapterId; public uint id; public uint modeIdx; public uint flags; }
        [StructLayout(LayoutKind.Sequential)] struct RATIONAL { public uint Num; public uint Den; }
        [StructLayout(LayoutKind.Sequential)] struct PATH_TGT { public LUID adapterId; public uint id; public uint modeIdx; public uint tech; public uint rot; public uint scl; public RATIONAL rr; public uint slo; public bool avail; public uint flags; }
        [StructLayout(LayoutKind.Sequential)] struct PATH { public PATH_SRC src; public PATH_TGT tgt; public uint flags; }
        [StructLayout(LayoutKind.Sequential)] struct MODE { public uint type; public uint id; public LUID adapterId; [MarshalAs(UnmanagedType.ByValArray, SizeConst=64)] public byte[] data; }
        [StructLayout(LayoutKind.Sequential)] struct HDR { public uint type; public uint size; public LUID adapterId; public uint id; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SRC_NAME { public HDR h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string gdi; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct TGT_NAME { public HDR h; public uint flags; public uint tech; public ushort mfg; public ushort prod; public uint conn; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string friendly; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string devPath; }

        [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(QDC f, out uint np, out uint nm);
        [DllImport("user32.dll")] static extern int QueryDisplayConfig(QDC f, ref uint np, [Out] PATH[] p, ref uint nm, [Out] MODE[] m, IntPtr t);
        [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref SRC_NAME i);
        [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TGT_NAME i);

        public static string[] GetActivePaths() {
            uint np, nm;
            if (GetDisplayConfigBufferSizes(QDC.OnlyActivePaths, out np, out nm) != 0) return new string[0];
            var paths = new PATH[np]; var modes = new MODE[nm];
            if (QueryDisplayConfig(QDC.OnlyActivePaths, ref np, paths, ref nm, modes, IntPtr.Zero) != 0) return new string[0];
            var list = new List<string>();
            for (int i = 0; i < (int)np; i++) {
                var s = new SRC_NAME(); s.h.type = 1; s.h.size = (uint)Marshal.SizeOf(typeof(SRC_NAME));
                s.h.adapterId = paths[i].src.adapterId; s.h.id = paths[i].src.id;
                DisplayConfigGetDeviceInfo(ref s);
                var t = new TGT_NAME(); t.h.type = 2; t.h.size = (uint)Marshal.SizeOf(typeof(TGT_NAME));
                t.h.adapterId = paths[i].tgt.adapterId; t.h.id = paths[i].tgt.id;
                DisplayConfigGetDeviceInfo(ref t);
                list.Add(string.Format("{0}|{1}|{2}|{3}", s.gdi, t.friendly, t.devPath, paths[i].src.id));
            }
            return list.ToArray();
        }
    }
}
'@
        Add-Type -TypeDefinition $csCode -ErrorAction Stop
    }

    $screens = [System.Windows.Forms.Screen]::AllScreens
    $map = @{}

    $paths = [SysAdminSuite.DisplayConfigHelper]::GetActivePaths()
    # Assign Settings display numbers: Windows uses source-id order (0-based) → 1-based
    $sortedPaths = $paths | Sort-Object { [int]($_ -split '\|')[3] }
    $settingsNum = 1
    foreach ($entry in $sortedPaths) {
        $parts = $entry -split '\|', 4
        $gdiName     = $parts[0]   # \\.\DISPLAY40
        $friendly    = $parts[1]   # 27G1H
        $devPath     = $parts[2]   # \\?\DISPLAY#IOCFFFF#...
        # parts[3] is the source-id used for sort order above

        # Extract PnP hardware-ID segment from device path
        # devPath looks like: \\?\DISPLAY#TSB0206#1&8713bca&0&UID0#{guid}
        $hwIdSegment = $null
        if ($devPath -match 'DISPLAY#([^#]+)#') { $hwIdSegment = $Matches[1] }

        $screen = $screens | Where-Object { $_.DeviceName -eq $gdiName }

        $map[$gdiName] = [PSCustomObject]@{
            SettingsDisplayNumber = $settingsNum
            DeviceName            = $gdiName
            MonitorName           = $friendly
            HardwareIdSegment     = $hwIdSegment
            IsPrimary             = if ($screen) { $screen.Primary } else { $false }
            BoundsX               = if ($screen) { $screen.Bounds.X } else { $null }
            BoundsY               = if ($screen) { $screen.Bounds.Y } else { $null }
            BoundsWidth           = if ($screen) { $screen.Bounds.Width } else { $null }
            BoundsHeight          = if ($screen) { $screen.Bounds.Height } else { $null }
        }
        $settingsNum++
    }
    return $map
}

function Get-MonitorInfo {
    [CmdletBinding()]
    param()

    $monitors = Get-WmiObject -Namespace root\wmi -Class WmiMonitorID
    $desktopMonitors = Get-WmiObject Win32_DesktopMonitor
    $videoAdapters = Get-WmiObject Win32_VideoController

    # Build display device map for display number / bounds / primary lookup
    $displayMap = @{}
    try { $displayMap = Get-DisplayDeviceMap } catch { Write-Verbose "Display device map unavailable: $_" }

    $monitorData = @()

    foreach ($monitor in $monitors) {
        $instanceName = $monitor.InstanceName

        $modelBytes = $monitor.UserFriendlyName | Where-Object { $_ -ne 0 }
        $model = if ($modelBytes.Count -gt 0) { [System.Text.Encoding]::ASCII.GetString($modelBytes -as [byte[]]) } else { "Unknown" }

        $serialBytes = $monitor.SerialNumberID | Where-Object { $_ -ne 0 }
        $serial = if ($serialBytes.Count -gt 0) { [System.Text.Encoding]::ASCII.GetString($serialBytes -as [byte[]]) } else { "Unknown" }

        $manufacturerBytes = $monitor.ManufacturerName | Where-Object { $_ -ne 0 }
        $manufacturer = if ($manufacturerBytes.Count -gt 0) { [System.Text.Encoding]::ASCII.GetString($manufacturerBytes -as [byte[]]) } else { "Unknown" }

        $resolution = Get-NativeResolution -InstanceName $instanceName
        if ($resolution -eq "Unknown") {
            $desktopMonitor = $desktopMonitors | Where-Object { $_.PNPDeviceID -like "*$($instanceName.split('\')[0])*" }
            $resolution = if ($desktopMonitor) { "$($desktopMonitor.ScreenWidth)x$($desktopMonitor.ScreenHeight)" } else { "Unknown" }
        }

        $connectionType = Get-ConnectionType -InstanceName $instanceName

        $adapterName = "Unknown"
        foreach ($adapter in $videoAdapters) {
            if ($instanceName -like "*$($adapter.DeviceID)*" -or $model -like "*$($adapter.Name)*") {
                $adapterName = $adapter.Name
                break
            }
        }

        # Match this WMI monitor to a display config entry by hardware-ID segment
        # InstanceName: DISPLAY\DELA0EC\5&abc_0  =>  middle segment = DELA0EC
        $hwIdSegment = ($instanceName -split '\\')[1]
        $matched = $null
        foreach ($entry in $displayMap.Values) {
            if ($hwIdSegment -and $entry.HardwareIdSegment -and
                $hwIdSegment -ieq $entry.HardwareIdSegment) {
                $matched = $entry
                break
            }
        }

        $settingsNum   = if ($matched) { $matched.SettingsDisplayNumber } else { $null }
        $isPrimary     = if ($matched) { $matched.IsPrimary } else { $null }
        $bounds        = if ($matched) { '{0},{1} {2}x{3}' -f $matched.BoundsX, $matched.BoundsY, $matched.BoundsWidth, $matched.BoundsHeight } else { 'Unknown' }
        $deviceName    = if ($matched) { $matched.DeviceName } else { 'Unknown' }

        $monitorData += [PSCustomObject]@{
            DisplayNumber = $settingsNum
            IsPrimary     = $isPrimary
            Model         = $model
            Serial        = $serial
            Manufacturer  = $manufacturer
            Resolution    = $resolution
            ScreenBounds  = $bounds
            Connection    = $connectionType
            DevicePath    = $deviceName
            Adapter       = $adapterName
        }
    }

    return $monitorData
}

function Reset-DisplayDeviceCache {
    <#
    .SYNOPSIS
        Forces Windows and DisplayLink drivers to re-enumerate connected monitors.
    .DESCRIPTION
        Stale EDID data (e.g. a TOSHIBA-TV that is no longer connected) persists
        because USB dock chipsets cache the last-seen monitor identity.  This function
        flushes that cache by:
          1. Disabling then re-enabling every DisplayLink USB display adapter via
             pnputil (requires elevation).
          2. Triggering a system-wide PnP device rescan so the OS rebuilds the
             WmiMonitorID / Win32_PnPEntity / QueryDisplayConfig tables.
          3. Waiting a configurable settle period for the dock firmware to
             re-negotiate EDID with whatever is physically attached.

        Run Get-MonitorInfo after this to see the refreshed state, or use
        Invoke-MonitorDiff to capture before/after automatically.
    .PARAMETER SettleSeconds
        How long to wait after the adapter cycle for the dock to re-negotiate.
        Default is 5 seconds.  Increase for slow docks or KVM switches.
    .PARAMETER IncludeNonDisplayLink
        Also cycle non-DisplayLink monitor PnP entities (generic PnP monitors).
        Off by default because it is rarely needed and can briefly blank all screens.
    .EXAMPLE
        Reset-DisplayDeviceCache
        # Cycles DisplayLink adapters, waits 5 s, ready for Get-MonitorInfo.
    .EXAMPLE
        Reset-DisplayDeviceCache -SettleSeconds 10
        # Longer settle for a sluggish dock.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [int]$SettleSeconds = 5,
        [switch]$IncludeNonDisplayLink
    )

    # --- require elevation ---
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw 'Reset-DisplayDeviceCache requires an elevated (Run as Administrator) session to cycle PnP devices.'
    }

    # --- locate DisplayLink USB display adapters ---
    $dlAdapters = Get-CimInstance Win32_PnPEntity |
        Where-Object { $_.DeviceID -like 'USB\VID_17E9*' -and $_.PNPClass -eq 'Display' }

    if (-not $dlAdapters -and -not $IncludeNonDisplayLink) {
        Write-Warning 'No DisplayLink display adapters found.  Use -IncludeNonDisplayLink to cycle generic monitor devices.'
        return
    }

    $targets = @($dlAdapters)
    if ($IncludeNonDisplayLink) {
        $monEntities = Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Monitor'" |
            Where-Object { $_.Status -eq 'OK' }
        $targets += @($monEntities)
    }

    foreach ($dev in $targets) {
        $id = $dev.DeviceID
        if ($PSCmdlet.ShouldProcess($id, 'Disable + Re-enable PnP device')) {
            Write-Verbose "Cycling device: $($dev.Name) [$id]"
            try {
                & pnputil /disable-device "$id" 2>&1 | Write-Verbose
            } catch {
                Write-Warning "Failed to disable $id : $_"
            }
        }
    }

    # Brief pause between disable and enable so dock firmware drops EDID
    Start-Sleep -Seconds 1

    foreach ($dev in $targets) {
        $id = $dev.DeviceID
        if ($PSCmdlet.ShouldProcess($id, 'Re-enable PnP device')) {
            try {
                & pnputil /enable-device "$id" 2>&1 | Write-Verbose
            } catch {
                Write-Warning "Failed to enable $id : $_"
            }
        }
    }

    # --- PnP rescan to rebuild WMI / CIM tables ---
    if ($PSCmdlet.ShouldProcess('System PnP tree', 'Rescan devices')) {
        Write-Verbose 'Triggering PnP device rescan...'
        & pnputil /scan-devices 2>&1 | Write-Verbose
    }

    Write-Host "Waiting $SettleSeconds seconds for dock firmware to re-negotiate..." -ForegroundColor Yellow
    Start-Sleep -Seconds $SettleSeconds
    Write-Host 'Display device cache reset complete.  Run Get-MonitorInfo to see current state.' -ForegroundColor Green
}

function Invoke-MonitorDiff {
    <#
    .SYNOPSIS
        Captures a before snapshot, optionally resets the display cache, then
        captures an after snapshot and outputs a structured diff.
    .DESCRIPTION
        Useful for analysing cable swaps, dock reconnections, and driver behaviour.
        Each monitor is keyed by its WMI InstanceName (hardware-ID + instance path).
        The diff shows monitors that Appeared, Disappeared, or Changed properties.

        If -Reset is specified, Reset-DisplayDeviceCache is called between snapshots
        (requires elevation).  Without -Reset, you are expected to perform the
        physical change yourself between the "before" and "after" prompts.
    .PARAMETER BeforeSnapshot
        Supply a previously captured snapshot (output of Get-MonitorInfo) to skip
        the interactive before-capture.  Useful for scripted pipelines.
    .PARAMETER Reset
        Automatically call Reset-DisplayDeviceCache between snapshots.
    .PARAMETER SettleSeconds
        Passed through to Reset-DisplayDeviceCache when -Reset is used.
    .PARAMETER NonInteractive
        Skip the interactive "press Enter" prompt.  Assumes the physical change
        has already been made or -Reset will handle it.
    .EXAMPLE
        Invoke-MonitorDiff
        # Interactive: captures before, prompts you to swap cables, captures after.
    .EXAMPLE
        $before = Get-MonitorInfo; Invoke-MonitorDiff -BeforeSnapshot $before -NonInteractive
    #>
    [CmdletBinding()]
    param(
        [PSObject[]]$BeforeSnapshot,
        [switch]$Reset,
        [int]$SettleSeconds = 5,
        [switch]$NonInteractive
    )

    # --- before ---
    if ($BeforeSnapshot) {
        $before = $BeforeSnapshot
        Write-Host 'Using supplied before-snapshot.' -ForegroundColor Cyan
    } else {
        Write-Host 'Capturing BEFORE snapshot...' -ForegroundColor Cyan
        $before = Get-MonitorInfo
    }

    Write-Host ''
    Write-Host ('  BEFORE: {0} monitor(s) detected' -f $before.Count) -ForegroundColor White
    foreach ($m in $before) {
        Write-Host ('    [{0}] {1}  Primary={2}  Bounds={3}  Conn={4}' -f
            $m.DisplayNumber, $m.Model, $m.IsPrimary, $m.ScreenBounds, $m.Connection) -ForegroundColor DarkGray
    }
    Write-Host ''

    # --- change ---
    if ($Reset) {
        Reset-DisplayDeviceCache -SettleSeconds $SettleSeconds
    } elseif (-not $NonInteractive) {
        Write-Host 'Perform the physical change now (swap cables, unplug dock, etc.).' -ForegroundColor Yellow
        Write-Host 'Press ENTER when ready to capture the AFTER snapshot...' -ForegroundColor Yellow
        Read-Host | Out-Null
    }

    # --- after ---
    Write-Host 'Capturing AFTER snapshot...' -ForegroundColor Cyan
    $after = Get-MonitorInfo

    Write-Host ('  AFTER:  {0} monitor(s) detected' -f $after.Count) -ForegroundColor White
    foreach ($m in $after) {
        Write-Host ('    [{0}] {1}  Primary={2}  Bounds={3}  Conn={4}' -f
            $m.DisplayNumber, $m.Model, $m.IsPrimary, $m.ScreenBounds, $m.Connection) -ForegroundColor DarkGray
    }
    Write-Host ''

    # --- diff keyed on Model+Serial (unique per physical monitor) ---
    $beforeByKey = @{}; foreach ($m in $before) { $beforeByKey["$($m.Model)|$($m.Serial)"] = $m }
    $afterByKey  = @{}; foreach ($m in $after)  { $afterByKey["$($m.Model)|$($m.Serial)"]  = $m }

    $allKeys = @($beforeByKey.Keys) + @($afterByKey.Keys) | Sort-Object -Unique
    $diffResults = @()

    foreach ($key in $allKeys) {
        $b = $beforeByKey[$key]
        $a = $afterByKey[$key]
        $keyModel = ($key -split '\|', 2)[0]

        if ($b -and -not $a) {
            $diffResults += [PSCustomObject]@{
                Status  = 'Disappeared'
                Model   = $keyModel
                Before  = '{0} Display#{1} Primary={2} Bounds={3} Conn={4}' -f $b.Manufacturer, $b.DisplayNumber, $b.IsPrimary, $b.ScreenBounds, $b.Connection
                After   = '-'
                Changes = 'Monitor no longer reported by driver'
            }
        } elseif (-not $b -and $a) {
            $diffResults += [PSCustomObject]@{
                Status  = 'Appeared'
                Model   = $keyModel
                Before  = '-'
                After   = '{0} Display#{1} Primary={2} Bounds={3} Conn={4}' -f $a.Manufacturer, $a.DisplayNumber, $a.IsPrimary, $a.ScreenBounds, $a.Connection
                Changes = 'New monitor detected'
            }
        } else {
            # Both present — check for property changes
            $props = @('DisplayNumber','IsPrimary','Resolution','ScreenBounds','Connection','DevicePath','Adapter','Serial')
            $changed = @()
            foreach ($p in $props) {
                $bv = [string]$b.$p; $av = [string]$a.$p
                if ($bv -ne $av) { $changed += ('{0}: {1} -> {2}' -f $p, $bv, $av) }
            }
            $diffResults += [PSCustomObject]@{
                Status  = if ($changed) { 'Changed' } else { 'Unchanged' }
                Model   = $keyModel
                Before  = '{0} Display#{1} Primary={2} Bounds={3} Conn={4}' -f $b.Manufacturer, $b.DisplayNumber, $b.IsPrimary, $b.ScreenBounds, $b.Connection
                After   = '{0} Display#{1} Primary={2} Bounds={3} Conn={4}' -f $a.Manufacturer, $a.DisplayNumber, $a.IsPrimary, $a.ScreenBounds, $a.Connection
                Changes = if ($changed) { $changed -join '; ' } else { '' }
            }
        }
    }

    # --- summary ---
    Write-Host '=== MONITOR DIFF RESULTS ===' -ForegroundColor Cyan
    $disappeared = @($diffResults | Where-Object Status -eq 'Disappeared')
    $appeared    = @($diffResults | Where-Object Status -eq 'Appeared')
    $changed     = @($diffResults | Where-Object Status -eq 'Changed')
    $unchanged   = @($diffResults | Where-Object Status -eq 'Unchanged')

    if ($disappeared) {
        Write-Host "`n  DISAPPEARED ($($disappeared.Count)):" -ForegroundColor Red
        foreach ($d in $disappeared) { Write-Host "    - $($d.Model): $($d.Before)" -ForegroundColor Red }
    }
    if ($appeared) {
        Write-Host "`n  APPEARED ($($appeared.Count)):" -ForegroundColor Green
        foreach ($a in $appeared) { Write-Host "    + $($a.Model): $($a.After)" -ForegroundColor Green }
    }
    if ($changed) {
        Write-Host "`n  CHANGED ($($changed.Count)):" -ForegroundColor Yellow
        foreach ($c in $changed) { Write-Host "    ~ $($c.Model): $($c.Changes)" -ForegroundColor Yellow }
    }
    if ($unchanged) {
        Write-Host "`n  UNCHANGED ($($unchanged.Count)):" -ForegroundColor DarkGray
        foreach ($u in $unchanged) { Write-Host "    = $($u.Model)" -ForegroundColor DarkGray }
    }

    Write-Host ''
    return $diffResults
}

function Export-MonitorInfoHtml {
    <#
    .SYNOPSIS
        Generates a styled HTML report from Get-MonitorInfo and optional Invoke-MonitorDiff output.
    .DESCRIPTION
        Produces a dark-themed HTML report (matching the RPM-Recon style) containing:
          - A timestamped header with machine name
          - A monitor summary table with display numbers, models, bounds, connection types
          - An optional diff section showing Appeared / Disappeared / Changed / Unchanged monitors
          - A dock insights panel summarising DisplayLink adapter status and phantom detection
        The report is written to the specified path and optionally opened in the default browser.
    .PARAMETER MonitorInfo
        Output from Get-MonitorInfo.  If omitted, the function calls Get-MonitorInfo internally.
    .PARAMETER DiffResults
        Output from Invoke-MonitorDiff.  Optional — when supplied, a diff section is included.
    .PARAMETER OutputPath
        File path for the HTML output.  Defaults to a timestamped file in the current directory.
    .PARAMETER Open
        Open the report in the default browser after writing.
    .EXAMPLE
        Export-MonitorInfoHtml -Open
    .EXAMPLE
        $info = Get-MonitorInfo; $diff = Invoke-MonitorDiff -NonInteractive
        Export-MonitorInfoHtml -MonitorInfo $info -DiffResults $diff -OutputPath C:\Temp\monitors.html
    #>
    [CmdletBinding()]
    param(
        [PSObject[]]$MonitorInfo,
        [PSObject[]]$DiffResults,
        [string]$OutputPath,
        [switch]$Open
    )

    if (-not $MonitorInfo) { $MonitorInfo = Get-MonitorInfo }
    if (-not $OutputPath) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $OutputPath = Join-Path $PWD "MonitorInfo_$stamp.html"
    }

    $outDir = Split-Path $OutputPath -Parent
    if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    # --- Detect dock adapters ---
    $dlAdapters = @()
    try {
        $dlAdapters = @(Get-CimInstance Win32_PnPEntity |
            Where-Object { $_.DeviceID -like 'USB\VID_17E9*' -and $_.PNPClass -eq 'Display' })
    } catch {}

    $phantoms = @($MonitorInfo | Where-Object { -not $_.DisplayNumber -or $_.ScreenBounds -eq 'Unknown' })
    $active   = @($MonitorInfo | Where-Object { $_.DisplayNumber -and $_.ScreenBounds -ne 'Unknown' })

    # --- Build HTML ---
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $hostname  = $env:COMPUTERNAME

    # Monitor table rows
    $monitorRows = ''
    foreach ($m in ($MonitorInfo | Sort-Object { if ($_.DisplayNumber) { [int]$_.DisplayNumber } else { 999 } })) {
        $numDisplay = if ($m.DisplayNumber) { $m.DisplayNumber } else { '<span class="phantom">&#x2013;</span>' }
        $primaryBadge = if ($m.IsPrimary -eq $true) { '<span class="badge primary">PRIMARY</span>' }
                        elseif ($null -eq $m.IsPrimary)  { '<span class="badge disconnected">DISCONNECTED</span>' }
                        else { '' }
        $rowClass = if (-not $m.DisplayNumber -or $m.ScreenBounds -eq 'Unknown') { ' class="phantom-row"' } else { '' }
        $eModel      = [System.Net.WebUtility]::HtmlEncode($m.Model)
        $eMfr        = [System.Net.WebUtility]::HtmlEncode($m.Manufacturer)
        $eSerial     = [System.Net.WebUtility]::HtmlEncode($m.Serial)
        $eRes        = [System.Net.WebUtility]::HtmlEncode($m.Resolution)
        $eBounds     = [System.Net.WebUtility]::HtmlEncode($m.ScreenBounds)
        $eConn       = [System.Net.WebUtility]::HtmlEncode($m.Connection)
        $eDevPath    = [System.Net.WebUtility]::HtmlEncode($m.DevicePath)
        $monitorRows += @"
        <tr$rowClass>
            <td>$numDisplay</td>
            <td>$eModel</td>
            <td>$eMfr</td>
            <td>$eSerial</td>
            <td>$eRes</td>
            <td>$eBounds</td>
            <td>$eConn</td>
            <td>$eDevPath</td>
            <td>$primaryBadge</td>
        </tr>
"@
    }

    # Diff section
    $diffSection = ''
    if ($DiffResults) {
        $diffRows = ''
        foreach ($d in $DiffResults) {
            $statusClass = switch ($d.Status) {
                'Disappeared' { 'diff-gone' }
                'Appeared'    { 'diff-new' }
                'Changed'     { 'diff-changed' }
                default       { 'diff-same' }
            }
            $statusIcon = switch ($d.Status) {
                'Disappeared' { '&#x2796;' }
                'Appeared'    { '&#x2795;' }
                'Changed'     { '&#x2194;' }
                default       { '&#x2713;' }
            }
            $changesCell = if ($d.Changes) { [System.Net.WebUtility]::HtmlEncode($d.Changes) } else { '' }
            $eModel = [System.Net.WebUtility]::HtmlEncode($d.Model)
            $diffRows += @"
            <tr class="$statusClass">
                <td>$statusIcon $($d.Status)</td>
                <td>$eModel</td>
                <td>$([System.Net.WebUtility]::HtmlEncode($d.Before))</td>
                <td>$([System.Net.WebUtility]::HtmlEncode($d.After))</td>
                <td>$changesCell</td>
            </tr>
"@
        }
        $diffSection = @"
    <h2>&#x1F504; Cable-Swap / Configuration Diff</h2>
    <table>
        <thead><tr><th>Status</th><th>Model</th><th>Before</th><th>After</th><th>Changes</th></tr></thead>
        <tbody>$diffRows</tbody>
    </table>
"@
    }

    # Dock insights panel
    $dockPanel = ''
    $dockEntries = ''
    if ($dlAdapters.Count -gt 0) {
        foreach ($dl in $dlAdapters) {
            $dockEntries += "<li><strong>$($dl.Name)</strong> &mdash; <code>$($dl.DeviceID)</code> &mdash; Status: $($dl.Status)</li>`n"
        }
    }
    $phantomEntries = ''
    if ($phantoms.Count -gt 0) {
        foreach ($p in $phantoms) {
            $phantomEntries += "<li><strong>$($p.Model)</strong> ($($p.Manufacturer)) &mdash; Serial: $($p.Serial) &mdash; "
            $phantomEntries += "WMI reports Active but no display topology assigned. Likely cached EDID from dock firmware.</li>`n"
        }
    }
    if ($dockEntries -or $phantomEntries) {
        $dockPanel = @"
    <h2>&#x1F50C; Dock &amp; Adapter Insights</h2>
    <div class="insights">
"@
        if ($dockEntries) {
            $dockPanel += @"
        <h3>DisplayLink Adapters</h3>
        <ul>$dockEntries</ul>
"@
        }
        if ($phantomEntries) {
            $dockPanel += @"
        <h3>&#x26A0; Phantom Monitors (cached EDID)</h3>
        <ul class="phantom-list">$phantomEntries</ul>
        <p class="hint">Run <code>Reset-DisplayDeviceCache</code> in an elevated session to flush stale EDID, or disconnect the phantom display in Windows Settings.</p>
"@
        }
        $dockPanel += '    </div>'
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Monitor Report - $hostname</title>
<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; background: #0b0b0f; color: #eaeaf0; padding: 24px; margin: 0; }
  h1 { color: #8ed0ff; margin-bottom: 4px; }
  h2 { color: #c0c0d0; border-bottom: 1px solid #2a2a34; padding-bottom: 6px; margin-top: 28px; }
  h3 { color: #a0a0b8; }
  .meta { color: #888; font-size: 13px; margin-bottom: 18px; }
  .chip { display: inline-block; background: #1a1a22; border: 1px solid #2a2a34; padding: 3px 10px; border-radius: 999px; margin-right: 8px; font-size: 12px; }
  table { border-collapse: collapse; width: 100%; margin-top: 8px; }
  th, td { border: 1px solid #2a2a34; padding: 7px 10px; font-size: 13px; text-align: left; }
  th { background: #171720; color: #b0b0c0; font-weight: 600; }
  tr:nth-child(even) { background: #0f0f16; }
  tr:hover { background: #1a1a28; }
  .phantom-row { opacity: 0.5; background: #1a0a0a; }
  .phantom-row:hover { opacity: 0.8; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; }
  .primary { background: #1a3a1a; color: #6fdf6f; border: 1px solid #2a5a2a; }
  .disconnected { background: #3a1a1a; color: #df6f6f; border: 1px solid #5a2a2a; }
  .phantom { color: #ff6666; font-weight: bold; }
  .diff-gone { background: #2a0a0a; }
  .diff-new { background: #0a2a0a; }
  .diff-changed { background: #2a2a0a; }
  .diff-same { opacity: 0.6; }
  .insights { background: #12121a; border: 1px solid #2a2a34; border-radius: 8px; padding: 12px 18px; margin-top: 8px; }
  .phantom-list li { color: #ff9966; }
  .hint { color: #888; font-size: 12px; font-style: italic; margin-top: 8px; }
  code { background: #1a1a28; padding: 1px 5px; border-radius: 3px; font-size: 12px; color: #c0d0ff; }
  .summary-bar { margin: 12px 0; }
</style>
</head>
<body>
<h1>&#x1F5B5; Monitor Identification Report</h1>
<p class="meta">$hostname &mdash; $timestamp</p>
<div class="summary-bar">
    <span class="chip">Active: $($active.Count)</span>
    <span class="chip">Phantom: $($phantoms.Count)</span>
    <span class="chip">Total in WMI: $($MonitorInfo.Count)</span>
    <span class="chip">DisplayLink adapters: $($dlAdapters.Count)</span>
</div>

<h2>&#x1F4BB; Connected Displays</h2>
<table>
    <thead><tr>
        <th>#</th><th>Model</th><th>Mfg</th><th>Serial</th><th>Resolution</th>
        <th>Bounds</th><th>Connection</th><th>Device</th><th>Status</th>
    </tr></thead>
    <tbody>$monitorRows</tbody>
</table>
$diffSection
$dockPanel
</body>
</html>
"@

    Set-Content -LiteralPath $OutputPath -Value $html -Encoding UTF8
    Write-Host "HTML report written: $OutputPath" -ForegroundColor Green

    if ($Open) {
        Start-Process $OutputPath
    }

    return $OutputPath
}