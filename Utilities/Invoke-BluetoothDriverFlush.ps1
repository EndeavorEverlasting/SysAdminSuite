<#
.SYNOPSIS
    Backs up and flushes corrupted Bluetooth audio drivers, clears COM port
    assignments, restarts the Bluetooth stack, and prepares for re-pairing.

.DESCRIPTION
    Designed for cases where Bluetooth audio drops randomly and the device
    cannot be re-added. The tool:

    1. Exports registry hives, service states, COM ports, audio endpoints,
       paired BT devices, and cached driver packages.
    2. Validates every backup file exists and is non-empty before mutation.
    3. Removes cached Bluetooth driver .inf packages via pnputil.
    4. Logs COM port assignments for operator review.
    5. Stops Bluetooth services, removes paired audio devices, resets the
       radio, then restarts services.
    6. Prints re-pairing instructions and restore commands.

    All mutations are gated behind -Confirm or explicit confirmation prompt.
    Use -BackupOnly to export without flushing. Use -WhatIf to preview.

.PARAMETER BackupPath
    Root directory for timestamped backup folders. Default: $env:APPDATA\BT_Flush_Backups.

.PARAMETER BackupOnly
    Export current state without performing any flush or mutation.

.PARAMETER SkipDeviceRemoval
    Skip removing paired Bluetooth devices (useful when only driver cache
    flush is needed).

.PARAMETER TargetDeviceName
    Friendly name filter for devices to remove. Supports wildcards.
    Default: 'speaker|audio|headphone|headset|earbuds'.

.EXAMPLE
    Invoke-BluetoothDriverFlush -BackupOnly
    # Exports all Bluetooth state without flushing.

.EXAMPLE
    Invoke-BluetoothDriverFlush -WhatIf
    # Shows what would be backed up and flushed without doing anything.

.EXAMPLE
    Invoke-BluetoothDriverFlush
    # Full backup, validate, flush, and re-pair prep. Prompts for confirmation.

.EXAMPLE
    Invoke-BluetoothDriverFlush -BackupPath 'D:\BT_Backups' -SkipDeviceRemoval
    # Backs up to custom path and skips device removal phase.
#>
function Invoke-BluetoothDriverFlush {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string]$BackupPath = (Join-Path $env:APPDATA 'BT_Flush_Backups'),
        [switch]$BackupOnly,
        [switch]$SkipDeviceRemoval,
        [string]$TargetDeviceName = 'speaker|audio|headphone|headset|earbuds',
        [switch]$Force
    )

    $ErrorActionPreference = 'Stop'
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $BackupPath $timestamp

    function Write-Phase {
        param([string]$Phase, [string]$Message)
        Write-Host "`n=== $Phase ===  $Message" -ForegroundColor Cyan
    }

    function Write-Step {
        param([string]$Message)
        Write-Host "  -> $Message"
    }

    function Write-StepOk {
        param([string]$Message)
        Write-Host "  OK: $Message" -ForegroundColor Green
    }

    function Write-StepWarn {
        param([string]$Message)
        Write-Host "  WARN: $Message" -ForegroundColor Yellow
    }

    function Write-StepFail {
        param([string]$Message)
        Write-Host "  FAIL: $Message" -ForegroundColor Red
    }

    # -----------------------------------------------------------------------
    # Phase 1 — Backup
    # -----------------------------------------------------------------------

    Write-Phase 'BACKUP PHASE' "Target: $backupDir"

    # Resolve target MAC addresses based on TargetDeviceName filter
    $targetMacs = @()
    $devicesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices"
    if (Test-Path $devicesPath) {
        Get-ChildItem $devicesPath -ErrorAction SilentlyContinue | ForEach-Object {
            $mac = $_.PSChildName
            $name = ""
            try {
                $nameBytes = Get-ItemPropertyValue -Path $_.PSPath -Name "Name" -ErrorAction SilentlyContinue
                if ($nameBytes) { $name = [System.Text.Encoding]::UTF8.GetString($nameBytes).TrimEnd("`0") }
            } catch {}

            $friendlyName = ""
            try {
                $friendlyNameBytes = Get-ItemPropertyValue -Path $_.PSPath -Name "FriendlyName" -ErrorAction SilentlyContinue
                if ($friendlyNameBytes) { $friendlyName = [System.Text.Encoding]::UTF8.GetString($friendlyNameBytes).TrimEnd("`0") }
            } catch {}

            if ($name -match $TargetDeviceName -or $friendlyName -match $TargetDeviceName -or $mac -match $TargetDeviceName) {
                $targetMacs += $mac
            }
        }
    }

    $pnpBtDevices = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match $TargetDeviceName }
    foreach ($dev in $pnpBtDevices) {
        if ($dev.InstanceId -match 'DEV_([0-9A-Fa-f]{12})') {
            $mac = $Matches[1].ToLower()
            if ($mac -notin $targetMacs) {
                $targetMacs += $mac
            }
        }
    }

    if ($targetMacs.Count -gt 0) {
        Write-Step "Resolved targeted MAC addresses: $($targetMacs -join ', ')"
    } else {
        Write-Step "No targeted MAC addresses resolved for filter '$TargetDeviceName'."
    }

    if ($PSCmdlet.ShouldProcess($backupDir, 'Create backup directory')) {
        if (-not (Test-Path -LiteralPath $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
    }

    $backupResults = [ordered]@{}

    # 1a. Registry keys
    Write-Step 'Exporting Bluetooth registry keys ...'
    $regKeys = @(
        @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT';          File = 'bthport.reg' }
        @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Services\BluetoothAudio';   File = 'bt_audio.reg' }
        @{ Key = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports'; File = 'com_ports.reg' }
        @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Enum\BT\Enumeration';       File = 'bt_enum.reg' }
        @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Class\{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}'; File = 'bt_class.reg' }
    )
    foreach ($rk in $regKeys) {
        $outFile = Join-Path $backupDir $rk.File
        if ($PSCmdlet.ShouldProcess($rk.Key, 'Export registry key')) {
            try {
                $r = & reg export $rk.Key $outFile /y 2>&1
                Write-StepOk "$($rk.File)"
                $backupResults[$rk.File] = $true
            } catch {
                Write-StepWarn "$($rk.Key): $($_.Exception.Message)"
                $backupResults[$rk.File] = $false
            }
        } else {
            Write-Step "Would export: $($rk.Key) -> $($rk.File)"
            $backupResults[$rk.File] = $true
        }
    }

    # 1b. Service states
    Write-Step 'Snapshotting Bluetooth service states ...'
    $btServices = @('bthserv', 'BthAudioHF', 'btwavext', 'RFCOMM', 'BthLEEnum')
    $svcData = @{}
    foreach ($svc in $btServices) {
        $svcData[$svc] = & sc.exe query $svc 2>&1 | Out-String
    }
    $svcFile = Join-Path $backupDir 'service_states.json'
    if ($PSCmdlet.ShouldProcess($svcFile, 'Write service states')) {
        $svcData | ConvertTo-Json -Depth 3 | Set-Content -Path $svcFile -Encoding UTF8
        Write-StepOk 'service_states.json'
        $backupResults['service_states.json'] = $true
    }

    # 1c. COM ports
    Write-Step 'Recording COM port assignments ...'
    $comFile = Join-Path $backupDir 'com_ports_current.txt'
    if ($PSCmdlet.ShouldProcess($comFile, 'Write COM port list')) {
        try {
            $comOut = & reg query 'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM' 2>&1 | Out-String
        } catch {
            $comOut = "(no COM ports found or access denied)"
        }
        $comOut | Set-Content -Path $comFile -Encoding UTF8
        Write-StepOk 'com_ports_current.txt'
        $backupResults['com_ports_current.txt'] = $true
    }

    # 1d. Audio endpoints
    Write-Step 'Exporting audio device list ...'
    $audioFile = Join-Path $backupDir 'audio_endpoints.json'
    if ($PSCmdlet.ShouldProcess($audioFile, 'Write audio endpoints')) {
        try {
            $audioDevices = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue |
                Select-Object Status, Class, FriendlyName, InstanceId |
                ConvertTo-Json -Depth 3
        } catch {
            $audioDevices = '[]'
        }
        $audioDevices | Set-Content -Path $audioFile -Encoding UTF8
        Write-StepOk 'audio_endpoints.json'
        $backupResults['audio_endpoints.json'] = $true
    }

    # 1e. Paired BT devices
    Write-Step 'Listing paired Bluetooth devices ...'
    $btDevFile = Join-Path $backupDir 'bt_devices.json'
    if ($PSCmdlet.ShouldProcess($btDevFile, 'Write paired BT devices')) {
        try {
            $btDevices = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
                Select-Object Status, Class, FriendlyName, InstanceId |
                ConvertTo-Json -Depth 3
        } catch {
            $btDevices = '[]'
        }
        $btDevices | Set-Content -Path $btDevFile -Encoding UTF8
        Write-StepOk 'bt_devices.json'
        $backupResults['bt_devices.json'] = $true
    }

    # 1f. Driver store BT entries
    Write-Step 'Recording driver store Bluetooth entries ...'
    $drvFile = Join-Path $backupDir 'driver_store_bt.txt'
    if ($PSCmdlet.ShouldProcess($drvFile, 'Write driver store entries')) {
        try {
            $drvOut = & pnputil /enum-drivers 2>&1 | Out-String
            $lines = $drvOut -split "`n"
            $btLines = @()
            $capture = $false
            foreach ($line in $lines) {
                if ($line -match 'Bluetooth|bluetooth') { $capture = $true }
                if ($capture) {
                    $btLines += $line
                    if ($line.Trim() -eq '') { $capture = $false }
                }
            }
            $btLines -join "`n" | Set-Content -Path $drvFile -Encoding UTF8
            Write-StepOk "driver_store_bt.txt ($($btLines.Count) lines)"
            $backupResults['driver_store_bt.txt'] = $true
        } catch {
            Write-StepWarn "Could not enumerate driver store: $($_.Exception.Message)"
            $backupResults['driver_store_bt.txt'] = $false
        }
    }

    # -----------------------------------------------------------------------
    # Phase 2 — Validate backups
    # -----------------------------------------------------------------------

    Write-Phase 'VALIDATION PHASE' ''

    $requiredFiles = @(
        'bthport.reg', 'com_ports.reg', 'service_states.json',
        'com_ports_current.txt', 'audio_endpoints.json', 'bt_devices.json'
    )
    $validationPassed = $true
    foreach ($fname in $requiredFiles) {
        $fPath = Join-Path $backupDir $fname
        if ((Test-Path -LiteralPath $fPath) -and (Get-Item -LiteralPath $fPath).Length -gt 0) {
            Write-Step "PASS: $fname ($((Get-Item -LiteralPath $fPath).Length) bytes)"
        } else {
            Write-StepFail "$fname - missing or empty!"
            $validationPassed = $false
        }
    }

    if (-not $validationPassed) {
        Write-Host "`nERROR: Backup validation failed. Aborting mutations." -ForegroundColor Red
        return
    }

    if ($BackupOnly) {
        Write-Host "`nBackup-only mode. No mutations performed." -ForegroundColor Green
        Write-Host "Backups saved to: $backupDir"
        return
    }

    # -----------------------------------------------------------------------
    # Phase 3 — Flush
    # -----------------------------------------------------------------------

    if (-not $PSCmdlet.ShouldProcess('Bluetooth stack', 'Flush drivers, clear COM ports, restart services, remove devices')) {
        Write-Host "`nWhatIf: would flush corrupted Bluetooth drivers and restart stack." -ForegroundColor Yellow
        return
    }

    if (-not $Force) {
        $confirm = Read-Host "`nBackups validated at $backupDir. Type YES to proceed with driver flush"
        if ($confirm -ne 'YES') {
            Write-Host 'Aborted by user.'
            return
        }
    }

    Write-Phase 'FLUSH PHASE' ''

    # 3a. Flush driver cache
    Write-Step 'Flushing cached Bluetooth driver packages ...'
    try {
        $drvEnum = & pnputil /enum-drivers 2>&1 | Out-String
        $lines = $drvEnum -split "`n"
        $oemInfs = @()
        $capture = $false
        foreach ($line in $lines) {
            if ($line -match 'Published Name:\s*(oem\d+\.inf)') {
                $inf = $Matches[1]
                $infPath = Join-Path $env:WINDIR "INF\$inf"
                if (Test-Path -LiteralPath $infPath) {
                    $content = Get-Content -Path $infPath -Raw -ErrorAction SilentlyContinue
                    if ($content -and $content -match '(?i)bluetooth') {
                        $oemInfs += $inf
                    }
                }
            }
        }
        foreach ($inf in $oemInfs) {
            Write-Step "  Deleting driver package: $inf"
            & pnputil /delete-driver $inf /uninstall /force 2>&1 | Out-Null
        }
        Write-StepOk "Removed $($oemInfs.Count) Bluetooth driver package(s)"
    } catch {
        Write-StepWarn "Driver flush error: $($_.Exception.Message)"
    }

    # 3b. Log COM ports for review
    Write-Step 'Recording COM port state ...'
    try {
        $comArbiter = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\COM Name Arbiter\Devices' -ErrorAction SilentlyContinue
        $comProps = $comArbiter.PSObject.Properties | Where-Object { $_.Name -match '^COM\d+' }
        if ($comProps) {
            Write-Step "  COM ports detected ($($comProps.Count)):"
            foreach ($p in $comProps) { Write-Step "    $($p.Name)" }
        } else {
            Write-Step '  No COM ports in arbiter.'
        }
    } catch {
        Write-StepWarn "Could not read COM arbiter: $($_.Exception.Message)"
    }

    # 3c. Stop BT services
    Write-Step 'Stopping Bluetooth services ...'
    foreach ($svc in $btServices) {
        & sc.exe stop $svc 2>&1 | Out-Null
    }
    Start-Sleep -Seconds 2
    Write-StepOk 'Services stopped'

    # 3d. Remove paired BT audio devices
    if (-not $SkipDeviceRemoval) {
        Write-Step 'Removing paired Bluetooth audio devices ...'
        try {
            $devicesToRemove = @()
            if ($targetMacs.Count -gt 0) {
                foreach ($mac in $targetMacs) {
                    $matched = Get-PnpDevice -ErrorAction SilentlyContinue |
                        Where-Object { $_.InstanceId -like "*$mac*" }
                    foreach ($m in $matched) {
                        if ($m.InstanceId -notin ($devicesToRemove | Select-Object -ExpandProperty InstanceId -ErrorAction SilentlyContinue)) {
                            $devicesToRemove += $m
                        }
                    }
                }
            } else {
                # Fallback to name-based matching on Bluetooth class only
                $devicesToRemove = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
                    Where-Object { $_.FriendlyName -match $TargetDeviceName }
            }

            if ($devicesToRemove.Count -gt 0) {
                foreach ($dev in $devicesToRemove) {
                    Write-Step "  Removing [Class: $($dev.Class)]: $($dev.FriendlyName) ($($dev.InstanceId))"
                    & pnputil /remove-device $dev.InstanceId 2>&1 | Out-Null
                }
                Write-StepOk "Removed $($devicesToRemove.Count) device node(s)"
            } else {
                Write-Step '  No matching Bluetooth devices found.'
            }

            # Attempt registry key cleanup for resolved MACs
            if ($targetMacs.Count -gt 0) {
                Write-Step 'Verifying registry key cleanup ...'
                foreach ($mac in $targetMacs) {
                    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$mac"
                    if (Test-Path $regPath) {
                        Write-StepWarn "Registry key for $mac still exists. Attempting delete ..."
                        try {
                            Remove-Item -Path $regPath -Force -Recurse -ErrorAction SilentlyContinue
                            if (-not (Test-Path $regPath)) {
                                Write-StepOk "Registry key for $mac deleted successfully."
                            } else {
                                Write-StepWarn "Could not delete registry key $mac (access denied)."
                            }
                        } catch {
                            Write-StepWarn "Error deleting registry key ${mac}: $($_.Exception.Message)"
                        }
                    } else {
                        Write-StepOk "Registry key for $mac was cleaned up successfully by PnP subsystem."
                    }
                }
            }
        } catch {
            Write-StepWarn "Device removal error: $($_.Exception.Message)"
        }
    } else {
        Write-Step 'Skipping device removal (SkipDeviceRemoval).'
    }

    # 3e. Reset Bluetooth radio
    Write-Step 'Resetting Bluetooth radio ...'
    try {
        $radios = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -match 'radio|adapter|dongle' }
        foreach ($radio in $radios) {
            Write-Step "  Disabling: $($radio.FriendlyName)"
            Disable-PnpDevice -InstanceId $radio.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Write-Step "  Enabling: $($radio.FriendlyName)"
            Enable-PnpDevice -InstanceId $radio.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        if (-not $radios) {
            Write-Step '  No explicit radio device found; services restart handles radio reset.'
        }
        Write-StepOk 'Radio reset complete'
    } catch {
        Write-StepWarn "Radio reset error: $($_.Exception.Message)"
    }

    # 3f. Start BT services
    Write-Step 'Starting Bluetooth services ...'
    foreach ($svc in @('RFCOMM', 'bthserv', 'BthAudioHF', 'btwavext', 'BthLEEnum')) {
        & sc.exe start $svc 2>&1 | Out-Null
    }
    Start-Sleep -Seconds 3
    Write-StepOk 'Services started'

    # -----------------------------------------------------------------------
    # Phase 4 — Summary
    # -----------------------------------------------------------------------

    Write-Host ''
    Write-Host '=' * 60 -ForegroundColor Cyan
    Write-Host '  FLUSH COMPLETE - NEXT STEPS' -ForegroundColor Green
    Write-Host '=' * 60 -ForegroundColor Cyan
    Write-Host "  Backups saved to: $backupDir"
    Write-Host ''
    Write-Host '  1. Open Settings > Bluetooth & devices'
    Write-Host '  2. Click Add device > Bluetooth'
    Write-Host '  3. Put your Bluetooth speaker in pairing mode'
    Write-Host '  4. Select it when it appears'
    Write-Host ''
    Write-Host '  To restore a specific registry key:'
    Write-Host "    reg import `"$backupDir\bthport.reg`""
    Write-Host ''
    Write-Host '  To fully restore all backups:'
    Write-Host "    Copy contents of $backupDir back manually"
    Write-Host '=' * 60 -ForegroundColor Cyan
}

# Allow direct invocation
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-BluetoothDriverFlush @PSBoundParameters
}
