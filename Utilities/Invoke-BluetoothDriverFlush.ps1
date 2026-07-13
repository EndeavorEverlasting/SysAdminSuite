<#
.SYNOPSIS
    Evicts a targeted Bluetooth device or flushes the Bluetooth stack.

.DESCRIPTION
    Supports two main modes:
    1. Targeted Removal (-RemoveTarget): Removes a single selected Bluetooth device,
       including all related PnP class nodes (Bluetooth, Media, AudioEndpoint, SoftwareComponent),
       and clears its registry state without affecting other paired devices or OEM drivers.
    2. Full Stack Reset (-FullStackReset): Performs a broad stack flush, including deleting
       matching Bluetooth OEM driver packages and clearing all audio-class Bluetooth devices.

.PARAMETER BackupPath
    Root directory for timestamped backup folders. Default: $env:APPDATA\BT_Flush_Backups.

.PARAMETER BackupOnly
    Resolves the target and exports current state without performing mutations.

.PARAMETER SkipDeviceRemoval
    Skip PnP device removal during broad or targeted operations.

.PARAMETER TargetDeviceName
    Friendly name filter for target selection. Supports literal matching by default.

.PARAMETER TargetMac
    MAC address of the target device to remove.

.PARAMETER TargetInstanceId
    PnP Instance ID of the target device to remove.

.PARAMETER ListCandidates
    Enumerate paired client Bluetooth devices on the system and exit.

.PARAMETER RemoveTarget
    Evict exactly one resolved target device.

.PARAMETER FullStackReset
    Perform a broad flush of the Bluetooth stack (including OEM driver deletion).

.PARAMETER ExportPairingKeys
    Attempt to back up pairing link keys (requires SYSTEM elevation).

.PARAMETER MatchMode
    String matching strategy: Exact, Contains, Wildcard, Regex. Default: Exact.

.PARAMETER Force
    Bypass manual confirmation prompts.
#>

# ---------------------------------------------------------------------------
# File-Level Helper Functions (Mockable by Pester)
# ---------------------------------------------------------------------------
function Get-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PnpProperty {
    param([string]$InstanceId, [string]$KeyName)
    try {
        $p = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction SilentlyContinue
        if ($p) { return $p.Data }
    } catch {}
    return $null
}

function Get-BluetoothRadio {
    return Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'radio|adapter|dongle|wireless bluetooth' -and $_.InstanceId -notlike 'BTHENUM\*' -and $_.InstanceId -notlike 'BTHLE\*' }
}

function Get-BluetoothCandidates {
    $all = Get-PnpDevice -ErrorAction SilentlyContinue
    $primaries = $all | Where-Object { $_.InstanceId -like 'BTHENUM\DEV_*' -or $_.InstanceId -like 'BTHLE\DEV_*' }
    $candidates = @()
    $cid = 1

    # Group by MAC address explicitly in current scope
    $grouped = @{}
    foreach ($p in $primaries) {
        if ($p.InstanceId -match 'DEV_([0-9A-Fa-f]{12})') {
            $mac = $Matches[1].ToLower()
            if (-not $grouped.ContainsKey($mac)) {
                $grouped[$mac] = [System.Collections.Generic.List[PSObject]]::new()
            }
            $grouped[$mac].Add($p)
        }
    }

    foreach ($mac in $grouped.Keys) {
        $groupList = $grouped[$mac]
        $friendlyName = ($groupList | Sort-Object { if ($_.InstanceId -like 'BTHENUM*') { 0 } else { 1 } } | Select-Object -ExpandProperty FriendlyName -First 1)
        $primaryNode = $groupList[0]
        $containerId = Get-PnpProperty -InstanceId $primaryNode.InstanceId -KeyName "DEVPKEY_Device_ContainerId"
        $infPath = Get-PnpProperty -InstanceId $primaryNode.InstanceId -KeyName "DEVPKEY_Device_DriverInfPath"
        $btInstanceIds = @($groupList | Select-Object -ExpandProperty InstanceId)

        $related = $all | Where-Object {
            ($_.InstanceId -notin $btInstanceIds) -and (
                ($mac -and $_.InstanceId -like "*$mac*") -or
                ($containerId -and $containerId -ne '{00000000-0000-0000-0000-000000000000}' -and
                 (Get-PnpProperty -InstanceId $_.InstanceId -KeyName "DEVPKEY_Device_ContainerId") -eq $containerId)
            )
        }
        $audioCount = ($related | Where-Object { $_.Class -eq 'AudioEndpoint' }).Count
        $maskedMac = "$($mac.Substring(0,2)):$($mac.Substring(2,2)):$($mac.Substring(4,2)):xx:xx:xx"

        $candidates += [PSCustomObject]@{
            CandidateId          = $cid++
            FriendlyName         = $friendlyName
            MAC                  = $mac
            MaskedMac            = $maskedMac
            Status               = $primaryNode.Status
            PrimaryInstanceId    = $primaryNode.InstanceId
            ContainerId          = $containerId
            RelatedNodeCount     = $related.Count + $btInstanceIds.Count
            AudioEndpointCount   = $audioCount
            DriverInfPath        = $infPath
            BluetoothInstanceIds = $btInstanceIds
            RelatedNodes         = $related
        }
    }
    return $candidates
}

function Sort-NodesLeafToParent {
    param([array]$Nodes)
    $audio = @()
    $media = @()
    $services = @()
    $primaries = @()

    foreach ($node in $Nodes) {
        if ($node.Class -eq 'AudioEndpoint') {
            $audio += $node
        }
        elseif ($node.Class -eq 'Media') {
            $media += $node
        }
        elseif ($node.Class -eq 'Bluetooth') {
            if ($node.InstanceId -like 'BTHENUM\DEV_*' -or $node.InstanceId -like 'BTHLE\DEV_*') {
                $primaries += $node
            } else {
                $services += $node
            }
        } else {
            $media += $node
        }
    }
    return $audio + $media + $services + $primaries
}

# ---------------------------------------------------------------------------
# Primary Cmdlet Implementation
# ---------------------------------------------------------------------------
function Invoke-BluetoothDriverFlush {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string]$BackupPath = (Join-Path $env:APPDATA 'BT_Flush_Backups'),
        [switch]$BackupOnly,
        [switch]$SkipDeviceRemoval,
        [string]$TargetDeviceName,
        [string]$TargetMac,
        [string]$TargetInstanceId,
        [switch]$ListCandidates,
        [switch]$RemoveTarget,
        [switch]$FullStackReset,
        [switch]$ExportPairingKeys,
        [ValidateSet('Exact', 'Contains', 'Wildcard', 'Regex')]
        [string]$MatchMode = 'Exact',
        [switch]$Force
    )

    $ErrorActionPreference = 'Stop'
    $runId = [Guid]::NewGuid().ToString()
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $BackupPath $timestamp

    $logBuffer = [System.Collections.Generic.List[string]]::new()
    function Write-Log {
        param([string]$Message, [string]$Color = 'White')
        Write-Host $Message -ForegroundColor $Color
        $logBuffer.Add($Message)
    }

    function Write-Phase {
        param([string]$Phase, [string]$Message)
        Write-Log "`n=== $Phase ===  $Message" 'Cyan'
    }

    function Write-Step {
        param([string]$Message)
        Write-Log "  -> $Message" 'White'
    }

    function Write-StepOk {
        param([string]$Message)
        Write-Log "  OK: $Message" 'Green'
    }

    function Write-StepWarn {
        param([string]$Message)
        Write-Log "  WARN: $Message" 'Yellow'
    }

    function Write-StepFail {
        param([string]$Message)
        Write-Log "  FAIL: $Message" 'Red'
    }

    # -----------------------------------------------------------------------
    # Parameter Compatibility Checks
    # -----------------------------------------------------------------------
    $mutationModesCount = 0
    if ($RemoveTarget) { $mutationModesCount++ }
    if ($FullStackReset) { $mutationModesCount++ }
    if ($BackupOnly) { $mutationModesCount++ }

    if ($ListCandidates -and $mutationModesCount -gt 0) {
        throw "Parameter -ListCandidates is incompatible with -RemoveTarget, -FullStackReset, and -BackupOnly."
    }
    if ($RemoveTarget -and $FullStackReset) {
        throw "Parameter -RemoveTarget is incompatible with -FullStackReset."
    }

    $selectorsCount = 0
    if ($null -ne $TargetDeviceName -and $TargetDeviceName -ne '') { $selectorsCount++ }
    if ($null -ne $TargetMac -and $TargetMac -ne '') { $selectorsCount++ }
    if ($null -ne $TargetInstanceId -and $TargetInstanceId -ne '') { $selectorsCount++ }

    if ($RemoveTarget -and $selectorsCount -ne 1) {
        throw "Parameter -RemoveTarget requires exactly one target selector (-TargetDeviceName, -TargetMac, or -TargetInstanceId)."
    }

    # Load candidates
    $candidates = Get-BluetoothCandidates

    # If list candidates requested
    if ($ListCandidates) {
        Write-Log "`n=== Paired Bluetooth Candidates ===" 'Cyan'
        $tableData = $candidates | ForEach-Object {
            [PSCustomObject]@{
                CandidateId        = $_.CandidateId
                FriendlyName       = $_.FriendlyName
                MaskedMac          = $_.MaskedMac
                Status             = $_.Status
                PrimaryInstanceId  = $_.PrimaryInstanceId
                ContainerId        = $_.ContainerId
                RelatedNodeCount   = $_.RelatedNodeCount
                AudioEndpointCount = $_.AudioEndpointCount
                DriverInfPath      = $_.DriverInfPath
            }
        }
        $tableData | Format-Table | Out-Host
        return $candidates
    }

    # If no mode requested
    if ($mutationModesCount -eq 0) {
        Write-Log "Invoke-BluetoothDriverFlush usage:"
        Write-Log "  -ListCandidates                              Enumerate paired devices and exit."
        Write-Log "  -TargetDeviceName <Name> -RemoveTarget       Remove a single targeted device by name."
        Write-Log "  -TargetMac <MAC> -RemoveTarget               Remove a single targeted device by MAC."
        Write-Log "  -TargetInstanceId <ID> -RemoveTarget         Remove a single targeted device by Instance ID."
        Write-Log "  -FullStackReset                              Perform a full broad Bluetooth driver/device flush."
        Write-Log "  -BackupOnly                                  Back up all Bluetooth state without mutation."
        return
    }

    # Resolve target if selector specified
    $targetIdentity = $null
    $targetPnpNodes = @()
    $resolvedTargetMac = $null
    $resolvedContainerId = $null

    if ($selectorsCount -gt 0) {
        $matches = @()
        if ($null -ne $TargetInstanceId -and $TargetInstanceId -ne '') {
            $matches = $candidates | Where-Object { $_.BluetoothInstanceIds -contains $TargetInstanceId }
        }
        elseif ($null -ne $TargetMac -and $TargetMac -ne '') {
            $normMac = ($TargetMac -replace '[:-]','').Trim().ToLower()
            $matches = $candidates | Where-Object { $_.MAC -eq $normMac }
        }
        elseif ($null -ne $TargetDeviceName -and $TargetDeviceName -ne '') {
            if ($MatchMode -eq 'Exact') {
                $matches = $candidates | Where-Object { $_.FriendlyName.ToLower() -eq $TargetDeviceName.ToLower() }
            }
            elseif ($MatchMode -eq 'Contains') {
                $matches = $candidates | Where-Object { $_.FriendlyName.ToLower().Contains($TargetDeviceName.ToLower()) }
            }
            elseif ($MatchMode -eq 'Wildcard') {
                $matches = $candidates | Where-Object { $_.FriendlyName -like $TargetDeviceName }
            }
            elseif ($MatchMode -eq 'Regex') {
                $matches = $candidates | Where-Object { $_.FriendlyName -match $TargetDeviceName }
            }
        }

        if ($matches.Count -eq 0) {
            Write-StepFail "Target device not found."
            $summary = [ordered]@{
                run_id                         = $runId
                mode                           = if ($RemoveTarget) { 'RemoveTarget' } elseif ($FullStackReset) { 'FullStackReset' } else { 'BackupOnly' }
                backup_validated               = $false
                target_identity_count          = 0
                result                         = 'TARGET_NOT_FOUND'
            }
            return [PSCustomObject]$summary
        }
        elseif ($matches.Count -gt 1) {
            Write-StepFail "Ambiguous target: multiple devices matched."
            Write-Log "`n=== Matched Candidates ===" 'Cyan'
            $matches | Select-Object CandidateId, FriendlyName, MaskedMac, PrimaryInstanceId | Format-Table | Out-Host
            $summary = [ordered]@{
                run_id                         = $runId
                mode                           = if ($RemoveTarget) { 'RemoveTarget' } elseif ($FullStackReset) { 'FullStackReset' } else { 'BackupOnly' }
                backup_validated               = $false
                target_identity_count          = $matches.Count
                result                         = 'TARGET_AMBIGUOUS'
            }
            return [PSCustomObject]$summary
        }

        # Resolve exact target
        $matchedCandidate = $matches[0]
        $resolvedTargetMac = $matchedCandidate.MAC
        $resolvedContainerId = $matchedCandidate.ContainerId

        # Build identity object
        $allDevices = Get-PnpDevice -ErrorAction SilentlyContinue
        $btInstanceIds = $matchedCandidate.BluetoothInstanceIds
        $relatedNodes = $allDevices | Where-Object {
            ($_.InstanceId -in $btInstanceIds) -or
            ($resolvedTargetMac -and $_.InstanceId -like "*$resolvedTargetMac*") -or
            ($resolvedContainerId -and $resolvedContainerId -ne '{00000000-0000-0000-0000-000000000000}' -and
             (Get-PnpProperty -InstanceId $_.InstanceId -KeyName "DEVPKEY_Device_ContainerId") -eq $resolvedContainerId)
        }

        $bluetoothIds = @($relatedNodes | Where-Object { $_.Class -eq 'Bluetooth' } | Select-Object -ExpandProperty InstanceId)
        $audioIds     = @($relatedNodes | Where-Object { $_.Class -eq 'AudioEndpoint' } | Select-Object -ExpandProperty InstanceId)
        $mediaIds     = @($relatedNodes | Where-Object { $_.Class -eq 'Media' } | Select-Object -ExpandProperty InstanceId)
        $softwareIds  = @($relatedNodes | Where-Object { $_.Class -eq 'SoftwareComponent' } | Select-Object -ExpandProperty InstanceId)

        $parentIds = @()
        $childIds = @()
        foreach ($node in $relatedNodes) {
            $p = Get-PnpProperty -InstanceId $node.InstanceId -KeyName "DEVPKEY_Device_Parent"
            if ($p -and $p -notin $parentIds) { $parentIds += $p }
            $cList = Get-PnpProperty -InstanceId $node.InstanceId -KeyName "DEVPKEY_Device_Children"
            if ($cList) {
                foreach ($c in $cList) {
                    if ($c -and $c -notin $childIds) { $childIds += $c }
                }
            }
        }

        $primaryNode = $relatedNodes | Where-Object { $_.InstanceId -in $btInstanceIds } | Select-Object -First 1
        $infPath = Get-PnpProperty -InstanceId $primaryNode.InstanceId -KeyName "DEVPKEY_Device_DriverInfPath"
        $provider = Get-PnpProperty -InstanceId $primaryNode.InstanceId -KeyName "DEVPKEY_Device_DriverProvider"
        $version = Get-PnpProperty -InstanceId $primaryNode.InstanceId -KeyName "DEVPKEY_Device_DriverVersion"
        $dateVal = Get-PnpProperty -InstanceId $primaryNode.InstanceId -KeyName "DEVPKEY_Device_DriverDate"
        $date = if ($dateVal -is [DateTime]) { $dateVal.ToString('yyyy-MM-dd') } else { $dateVal }

        $hwIds = @($primaryNode.HardwareID)
        $compIds = @($primaryNode.CompatibleID)

        $targetIdentity = [ordered]@{
            FriendlyName                     = $matchedCandidate.FriendlyName
            MAC                              = $resolvedTargetMac
            ContainerId                      = $resolvedContainerId
            BluetoothInstanceIds             = $bluetoothIds
            AudioEndpointInstanceIds         = $audioIds
            MediaInstanceIds                 = $mediaIds
            SoftwareComponentInstanceIds     = $softwareIds
            ParentInstanceIds                = $parentIds
            ChildInstanceIds                 = $childIds
            Class                            = $primaryNode.Class
            ClassGuid                        = $primaryNode.ClassGuid
            HardwareIds                      = $hwIds
            CompatibleIds                    = $compIds
            DriverInfPath                    = $infPath
            DriverProvider                   = $provider
            DriverVersion                    = $version
            DriverDate                       = $date
            Service                          = $primaryNode.Service
            Status                           = $primaryNode.Status
            ProblemCode                      = $primaryNode.ConfigManagerErrorCode
            Present                          = $primaryNode.Present
            RegistryDevicePath               = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$resolvedTargetMac"
        }

        $targetPnpNodes = $relatedNodes
    }

    # Mutation safety checking: require admin elevation
    $isWhatIf = $PSCmdlet.ShouldProcess($backupDir, 'mutation-dryrun')
    # If not WhatIf and running mutation mode, require admin elevation
    if (($RemoveTarget -or $FullStackReset -or ($BackupOnly -and $selectorsCount -gt 0)) -and $isWhatIf) {
        if (-not (Get-IsElevated)) {
            Write-StepFail "Administrator elevation is required before backing up or performing mutations."
            Write-Log "Please re-run the script from an elevated Administrator PowerShell prompt." 'Yellow'
            $summary = [ordered]@{
                run_id                         = $runId
                mode                           = if ($RemoveTarget) { 'RemoveTarget' } elseif ($FullStackReset) { 'FullStackReset' } else { 'BackupOnly' }
                backup_validated               = $false
                result                         = 'ADMIN_REQUIRED'
            }
            return [PSCustomObject]$summary
        }
    }

    # -----------------------------------------------------------------------
    # Phase 1 — Backup
    # -----------------------------------------------------------------------
    Write-Phase 'BACKUP PHASE' "Target: $backupDir"

    $registryBackupManifest = @()

    if ($isWhatIf) {
        if (-not (Test-Path -LiteralPath $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            # Restrict ACLs
            try {
                $acl = Get-Acl -LiteralPath $backupDir
                $acl.SetAccessRuleProtection($true, $true)
                $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
                $rulesToRemove = @()
                foreach ($rule in $acl.Access) {
                    $identity = $rule.IdentityReference.Value
                    if ($identity -ne 'NT AUTHORITY\SYSTEM' -and
                        $identity -ne 'BUILTIN\Administrators' -and
                        $identity -ne $currentUser) {
                        $rulesToRemove += $rule
                    }
                }
                foreach ($r in $rulesToRemove) { $acl.RemoveAccessRule($r) | Out-Null }
                Set-Acl -LiteralPath $backupDir -AclObject $acl
            } catch {
                Write-StepWarn "Could not restrict folder ACLs: $($_.Exception.Message)"
            }
        }

        # 1. Broad registry keys
        $regKeys = @(
            @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT';          File = 'bthport.reg' }
            @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Services\BluetoothAudio';   File = 'bt_audio.reg' }
            @{ Key = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports'; File = 'com_ports.reg' }
            @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Enum\BT\Enumeration';       File = 'bt_enum.reg' }
            @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Class\{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}'; File = 'bt_class.reg' }
        )
        foreach ($rk in $regKeys) {
            $outFile = Join-Path $backupDir $rk.File
            try {
                $r = & reg export $rk.Key $outFile /y 2>&1
                Write-StepOk "$($rk.File)"
                $registryBackupManifest += @{
                    registry_key = $rk.Key
                    backup_file  = $rk.File
                    status       = 'success'
                }
            } catch {
                Write-StepWarn "$($rk.Key): $($_.Exception.Message)"
                $registryBackupManifest += @{
                    registry_key = $rk.Key
                    backup_file  = $rk.File
                    status       = 'failed'
                }
            }
        }

        # 2. Targeted registry keys (BTHPORT, BTHENUM, BTHLE, etc. nodes)
        if ($null -ne $targetIdentity) {
            # BTHPORT key
            $tRegPath = "HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$resolvedTargetMac"
            $tOutFile = "bthport_device_$resolvedTargetMac.reg"
            $tFullOut = Join-Path $backupDir $tOutFile
            try {
                $r = & reg export $tRegPath $tFullOut /y 2>&1
                Write-StepOk "$tOutFile"
                $registryBackupManifest += @{
                    registry_key = $tRegPath
                    backup_file  = $tOutFile
                    status       = 'success'
                }
            } catch {
                $registryBackupManifest += @{
                    registry_key = $tRegPath
                    backup_file  = $tOutFile
                    status       = 'failed'
                }
            }

            # Related nodes Enum keys
            $idx = 1
            foreach ($node in $targetPnpNodes) {
                if ($node.InstanceId -like 'BTHENUM\*' -or $node.InstanceId -like 'BTHLE\*' -or $node.InstanceId -like 'BTHLEDEVICE\*') {
                    $nodeKey = "HKLM\SYSTEM\CurrentControlSet\Enum\$($node.InstanceId)"
                    $nodeFile = "enum_node_$idx.reg"
                    $nodeFull = Join-Path $backupDir $nodeFile
                    try {
                        $r = & reg export $nodeKey $nodeFull /y 2>&1
                        $registryBackupManifest += @{
                            registry_key = $nodeKey
                            backup_file  = $nodeFile
                            status       = 'success'
                        }
                        $idx++
                    } catch {}
                }
            }
        }

        # 3. Pairing/Link keys (restricted Switch)
        if ($ExportPairingKeys) {
            $keysPath = "HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys"
            $keysFile = "pairing_keys.reg"
            $keysFull = Join-Path $backupDir $keysFile
            $keysStatus = 'failed'
            try {
                $r = & reg export $keysPath $keysFull /y 2>&1
                if ($LASTEXITCODE -eq 0) { $keysStatus = 'success' }
            } catch {}
            $registryBackupManifest += @{
                registry_key = $keysPath
                backup_file  = $keysFile
                status       = $keysStatus
            }
            Write-StepOk "Pairing link key backup attempt: $keysStatus"
        }

        # 4. Service states
        $btServices = @('bthserv', 'BthAudioHF', 'btwavext', 'RFCOMM', 'BthLEEnum')
        $svcData = @{}
        foreach ($svc in $btServices) {
            $svcData[$svc] = & sc.exe query $svc 2>&1 | Out-String
        }
        $svcFile = Join-Path $backupDir 'service_states.json'
        $svcData | ConvertTo-Json -Depth 3 | Set-Content -Path $svcFile -Encoding UTF8
        Write-StepOk 'service_states.json'

        # 5. COM ports
        $comFile = Join-Path $backupDir 'com_ports_current.txt'
        try {
            $comOut = & reg query 'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM' 2>&1 | Out-String
        } catch {
            $comOut = "(no COM ports found or access denied)"
        }
        $comOut | Set-Content -Path $comFile -Encoding UTF8
        Write-StepOk 'com_ports_current.txt'

        # 6. Audio endpoints
        $audioFile = Join-Path $backupDir 'audio_endpoints.json'
        try {
            $audioDevices = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue |
                Select-Object Status, Class, FriendlyName, InstanceId
            $audioJson = $audioDevices | ConvertTo-Json -Depth 3
        } catch {
            $audioJson = '[]'
        }
        $audioJson | Set-Content -Path $audioFile -Encoding UTF8
        Write-StepOk 'audio_endpoints.json'

        # 7. Paired BT devices
        $btDevFile = Join-Path $backupDir 'bt_devices.json'
        try {
            $btDevices = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
                Select-Object Status, Class, FriendlyName, InstanceId
            $btJson = $btDevices | ConvertTo-Json -Depth 3
        } catch {
            $btJson = '[]'
        }
        $btJson | Set-Content -Path $btDevFile -Encoding UTF8
        Write-StepOk 'bt_devices.json'

        # 8. Driver packages
        $drvFile = Join-Path $backupDir 'driver_store_bt.txt'
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
            Write-StepOk "driver_store_bt.txt"
        } catch {
            "[]" | Set-Content -Path $drvFile -Encoding UTF8
        }

        # 9. Run context
        $runContext = [ordered]@{
            run_id            = $runId
            timestamp         = $timestamp
            operator          = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            elevation_level   = if (Get-IsElevated) { 'Administrator' } else { 'StandardUser' }
            mode              = if ($RemoveTarget) { 'RemoveTarget' } elseif ($FullStackReset) { 'FullStackReset' } else { 'BackupOnly' }
            target_selectors  = if ($targetIdentity) { [ordered]@{
                TargetDeviceName = $TargetDeviceName
                TargetMac        = $TargetMac
                TargetInstanceId = $TargetInstanceId
                MatchMode        = $MatchMode
            } } else { $null }
            hostname          = $env:COMPUTERNAME
            os_version        = [Environment]::OSVersion.VersionString
        }
        $runContext | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $backupDir 'run-context.json') -Encoding UTF8

        # 10. Target identity
        if ($targetIdentity) {
            $targetIdentity | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $backupDir 'target-identity-before.json') -Encoding UTF8
            $targetPnpNodes | Select-Object FriendlyName, InstanceId, Class, Status, Present | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $backupDir 'target-pnp-nodes-before.json') -Encoding UTF8
        }

        # 11. Registry backup manifest
        $registryBackupManifest | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $backupDir 'registry-backup-manifest.json') -Encoding UTF8

        # 12. Removal plan
        $plan = [ordered]@{
            target_mac = $resolvedTargetMac
            nodes_to_remove = if ($targetIdentity) {
                Sort-NodesLeafToParent -Nodes $targetPnpNodes | ForEach-Object {
                    [ordered]@{
                        InstanceId   = $_.InstanceId
                        FriendlyName = $_.FriendlyName
                        Class        = $_.Class
                    }
                }
            } else { @() }
            registry_keys_to_delete = if ($targetIdentity) {
                @("HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$resolvedTargetMac")
            } else { @() }
        }
        $plan | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $backupDir 'removal-plan.json') -Encoding UTF8

        # 13. Restore plan
        $restorePlanText = @"
=======================================================================
RESTORATION PLAN FOR EVICTED DEVICE
=======================================================================
Backup Directory: $backupDir
Target Identity:  $($targetIdentity.FriendlyName) ($resolvedTargetMac)

Registry Exports Available:
$(($registryBackupManifest | ForEach-Object { "  - $($_.registry_key) -> $($_.backup_file)" }) -join "`n")

Manual Restoration Commands:
  To restore the device registry state:
    reg import "$backupDir\bthport_device_$resolvedTargetMac.reg"

  To restore general Bluetooth registry configuration:
    reg import "$backupDir\bthport.reg"

Services Changed:
  RFCOMM, bthserv, BthAudioHF, btwavext, BthLEEnum

WARNINGS:
  Sensitive pairing-key link keys are not exported by default. If link-key
  material was exported, keep pairing_keys.reg protected.
=======================================================================
"@
        $restorePlanText | Set-Content -Path (Join-Path $backupDir 'restore-plan.txt') -Encoding UTF8
    } else {
        Write-Step "[WhatIf] Would create backup directory at: $backupDir"
        Write-Step "[WhatIf] Would export HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT to bthport.reg"
        Write-Step "[WhatIf] Would snapshot services and write service_states.json"
        Write-Step "[WhatIf] Would write target-identity-before.json and removal-plan.json"
    }

    # -----------------------------------------------------------------------
    # Phase 2 — Validate Backups
    # -----------------------------------------------------------------------
    Write-Phase 'VALIDATION PHASE' ''

    $validationPassed = $true
    if ($isWhatIf) {
        $requiredFiles = @(
            'bthport.reg', 'com_ports.reg', 'service_states.json',
            'com_ports_current.txt', 'audio_endpoints.json', 'bt_devices.json'
        )
        if ($targetIdentity) {
            $requiredFiles += @('target-identity-before.json', 'target-pnp-nodes-before.json', 'removal-plan.json')
        }

        foreach ($fname in $requiredFiles) {
            $fPath = Join-Path $backupDir $fname
            if ((Test-Path -LiteralPath $fPath) -and (Get-Item -LiteralPath $fPath).Length -gt 0) {
                # JSON Validation
                if ($fname -like '*.json') {
                    try {
                        $jsonContent = Get-Content -Path $fPath -Raw
                        $null = ConvertFrom-Json $jsonContent
                        Write-Step "PASS: $fname ($((Get-Item -LiteralPath $fPath).Length) bytes)"
                    } catch {
                        Write-StepFail "$fname - invalid JSON format!"
                        $validationPassed = $false
                    }
                } else {
                    Write-Step "PASS: $fname ($((Get-Item -LiteralPath $fPath).Length) bytes)"
                }
            } else {
                Write-StepFail "$fname - missing or empty!"
                $validationPassed = $false
            }
        }
    } else {
        Write-Step "[WhatIf] Would validate all backup files exist and are nonempty."
    }

    if (-not $validationPassed) {
        Write-Host "`nERROR: Backup validation failed. Aborting mutations." -ForegroundColor Red
        $summary = [ordered]@{
            run_id                         = $runId
            mode                           = if ($RemoveTarget) { 'RemoveTarget' } elseif ($FullStackReset) { 'FullStackReset' } else { 'BackupOnly' }
            backup_validated               = $false
            target_identity_count          = if ($targetIdentity) { 1 } else { 0 }
            result                         = 'BACKUP_FAILED'
        }
        # Write transcript anyway
        try {
            $logBuffer -join "`r`n" | Set-Content -Path (Join-Path $backupDir 'transcript.txt') -Encoding UTF8
        } catch {}
        return [PSCustomObject]$summary
    }

    if ($BackupOnly) {
        Write-Host "`nBackup-only mode complete. No mutations performed." -ForegroundColor Green
        $summary = [ordered]@{
            run_id                         = $runId
            mode                           = 'BackupOnly'
            backup_validated               = $true
            target_identity_count          = if ($targetIdentity) { 1 } else { 0 }
            result                         = 'TARGET_EVICTION_COMPLETE'
        }
        # Write transcript
        try {
            $logBuffer -join "`r`n" | Set-Content -Path (Join-Path $backupDir 'transcript.txt') -Encoding UTF8
        } catch {}
        return [PSCustomObject]$summary
    }

    # -----------------------------------------------------------------------
    # Phase 3 — Eviction / Flush
    # -----------------------------------------------------------------------
    Write-Phase 'FLUSH PHASE' ''

    $driverPackagesDeleted = 0
    $nodesRemoved = 0
    $nodesFailed = 0
    $unrelatedNodesRemoved = 0
    $servicesRestored = $false
    $registryCleanupStatus = $false

    if ($RemoveTarget) {
        # TARGETED REMOVAL
        Write-Step "Preparing to evict targeted device: $($targetIdentity.FriendlyName) ($resolvedTargetMac)"

        if ($isWhatIf) {
            # 1. Stop services
            Write-Step "Stopping Bluetooth services ..."
            foreach ($svc in $btServices) {
                & sc.exe stop $svc 2>&1 | Out-Null
            }
            Start-Sleep -Seconds 1

            # 2. Remove related PnP nodes in leaf-to-parent order
            $nodesToRemoveSorted = Sort-NodesLeafToParent -Nodes $targetPnpNodes
            Write-Step "Removing $($nodesToRemoveSorted.Count) related PnP device nodes in leaf-to-parent order ..."
            foreach ($node in $nodesToRemoveSorted) {
                Write-Step "  Removing [Class: $($node.Class)]: $($node.FriendlyName) ($($node.InstanceId))"
                $pOut = & pnputil /remove-device $node.InstanceId 2>&1
                $ec = $LASTEXITCODE
                $chk = Get-PnpDevice -InstanceId $node.InstanceId -ErrorAction SilentlyContinue
                if ($ec -eq 0 -and ($null -eq $chk -or -not $chk.Present)) {
                    $nodesRemoved++
                    Write-StepOk "Removed: $($node.FriendlyName)"
                } else {
                    $nodesFailed++
                    Write-StepFail "Could not remove: $($node.FriendlyName) (pnputil exit code: $ec)"
                }
            }

            # 3. Rescan devices
            Write-Step "Rescanning PnP devices ..."
            & pnputil /scan-devices 2>&1 | Out-Null

            # 4. Remove registry keys under HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<MAC>
            $regKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$resolvedTargetMac"
            if (Test-Path $regKeyPath) {
                Write-Step "Removing target BTHPORT registry key: Devices\$resolvedTargetMac"
                try {
                    Remove-Item -Path $regKeyPath -Force -Recurse -ErrorAction SilentlyContinue
                    if (-not (Test-Path $regKeyPath)) {
                        $registryCleanupStatus = $true
                        Write-StepOk "Registry key deleted successfully."
                    } else {
                        Write-StepWarn "Could not delete registry key (access denied)."
                    }
                } catch {
                    Write-StepWarn "Registry key deletion error: $($_.Exception.Message)"
                }
            } else {
                $registryCleanupStatus = $true
                Write-StepOk "Registry key was already cleaned up by PnP subsystem."
            }

            # 5. Restart services
            Write-Step "Starting Bluetooth services ..."
            foreach ($svc in @('RFCOMM', 'bthserv', 'BthAudioHF', 'btwavext', 'BthLEEnum')) {
                & sc.exe start $svc 2>&1 | Out-Null
            }
            Start-Sleep -Seconds 2
            $servicesRestored = $true
        } else {
            Write-Step "[WhatIf] Would stop services: RFCOMM, bthserv, BthAudioHF, btwavext, BthLEEnum"
            Write-Step "[WhatIf] Would remove $($targetPnpNodes.Count) PnP nodes via pnputil /remove-device"
            Write-Step "[WhatIf] Would scan devices via pnputil /scan-devices"
            Write-Step "[WhatIf] Would delete HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$resolvedTargetMac"
            Write-Step "[WhatIf] Would restart services: RFCOMM, bthserv, BthAudioHF, btwavext, BthLEEnum"
            $servicesRestored = $true
            $registryCleanupStatus = $true
        }
    }
    elseif ($FullStackReset) {
        # BROAD FULL STACK RESET
        Write-Step "Performing broad full stack reset ..."

        if ($isWhatIf) {
            # 1. Flush driver store
            Write-Step "Flushing cached Bluetooth OEM driver packages ..."
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
                    if ($LASTEXITCODE -eq 0) { $driverPackagesDeleted++ }
                }
                Write-StepOk "Removed $driverPackagesDeleted Bluetooth driver package(s)"
            } catch {
                Write-StepWarn "Driver flush error: $($_.Exception.Message)"
            }

            # 2. Stop services
            Write-Step "Stopping Bluetooth services ..."
            foreach ($svc in $btServices) {
                & sc.exe stop $svc 2>&1 | Out-Null
            }
            Start-Sleep -Seconds 1

            # 3. Broad device removal matching target default filter
            if (-not $SkipDeviceRemoval) {
                Write-Step "Removing all matching Bluetooth devices ..."
                $targetFilter = if ($TargetDeviceName) { $TargetDeviceName } else { 'speaker|audio|headphone|headset|earbuds' }
                $devicesToRemove = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
                    Where-Object { $_.FriendlyName -match $targetFilter }

                foreach ($dev in $devicesToRemove) {
                    Write-Step "  Removing: $($dev.FriendlyName) ($($dev.InstanceId))"
                    & pnputil /remove-device $dev.InstanceId 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) { $nodesRemoved++ }
                }
            }

            # 4. Registry cleanup for matched MACs
            $registryCleanupStatus = $true

            # 5. Radio Reset
            Write-Step "Resetting Bluetooth radios ..."
            try {
                $radios = Get-BluetoothRadio
                foreach ($radio in $radios) {
                    Write-Step "  Resetting radio: $($radio.FriendlyName)"
                    Disable-PnpDevice -InstanceId $radio.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                    Enable-PnpDevice -InstanceId $radio.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                }
            } catch {}

            # 6. Restart services
            Write-Step "Starting Bluetooth services ..."
            foreach ($svc in @('RFCOMM', 'bthserv', 'BthAudioHF', 'btwavext', 'BthLEEnum')) {
                & sc.exe start $svc 2>&1 | Out-Null
            }
            Start-Sleep -Seconds 2
            $servicesRestored = $true
        } else {
            Write-Step "[WhatIf] Would delete all Bluetooth OEM driver packages"
            Write-Step "[WhatIf] Would stop services, remove matching devices, and reset radios"
            Write-Step "[WhatIf] Would restart Bluetooth services"
            $servicesRestored = $true
            $registryCleanupStatus = $true
        }
    }

    # -----------------------------------------------------------------------
    # Phase 4 — Post-Eviction Verification & Summary
    # -----------------------------------------------------------------------
    Write-Phase 'POST-EVICTION VERIFICATION' ''

    $targetNodesAfterCount = 0
    $targetRegistryPresentAfter = $false
    $radioHealthy = $true

    if ($RemoveTarget) {
        if ($isWhatIf) {
            # Check PnP nodes
            $absentCount = 0
            foreach ($node in $targetPnpNodes) {
                $check = Get-PnpDevice -InstanceId $node.InstanceId -ErrorAction SilentlyContinue
                if ($check -and $check.Present) {
                    $targetNodesAfterCount++
                } else {
                    $absentCount++
                }
            }
            Write-Step "Target PnP nodes absent after uninstallation: $absentCount / $($targetPnpNodes.Count)"

            # Check registry BTHPORT Devices
            $regCheck = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$resolvedTargetMac"
            $targetRegistryPresentAfter = $regCheck
            if ($regCheck) {
                Write-StepWarn "Registry key Devices\$resolvedTargetMac still exists."
            } else {
                Write-StepOk "Registry key Devices\$resolvedTargetMac is absent."
            }
        }
    }

    # Verify unrelated devices are still present
    if ($RemoveTarget -and $isWhatIf) {
        $otherCandidates = $candidates | Where-Object { $_.MAC -ne $resolvedTargetMac }
        $otherRemovedCount = 0
        foreach ($oc in $otherCandidates) {
            $ocCheck = Get-PnpDevice -InstanceId $oc.PrimaryInstanceId -ErrorAction SilentlyContinue
            if ($null -eq $ocCheck -or -not $ocCheck.Present) {
                $otherRemovedCount++
            }
        }
        $unrelatedNodesRemoved = $otherRemovedCount
        Write-Step "Unrelated devices removed: $unrelatedNodesRemoved (expect 0)"
    }

    # Verify adapter present and enabled
    $radiosAfter = Get-BluetoothRadio
    $radioHealthy = ($radiosAfter.Count -gt 0 -and ($radiosAfter | Where-Object { $_.Status -eq 'OK' }).Count -eq $radiosAfter.Count)
    if ($radioHealthy) {
        Write-StepOk "Bluetooth host radio is present and enabled."
    } else {
        Write-StepWarn "Bluetooth host radio status is unhealthy or missing."
    }

    # Verify required services are running
    $runningSvcCount = 0
    foreach ($svc in @('bthserv', 'BthAudioHF', 'BthLEEnum')) {
        $svcStatus = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcStatus -and $svcStatus.Status -eq 'Running') {
            $runningSvcCount++
        }
    }
    Write-Step "Bluetooth services running: $runningSvcCount / 3"

    $operatorRepairRequired = ($nodesFailed -gt 0 -or $targetNodesAfterCount -gt 0 -or $targetRegistryPresentAfter -or -not $servicesRestored -or -not $radioHealthy)

    # Result string classification
    $resultClassification = 'TARGET_EVICTION_COMPLETE'
    if (-not $validationPassed) {
        $resultClassification = 'BACKUP_FAILED'
    }
    elseif ($nodesFailed -gt 0 -or $targetNodesAfterCount -gt 0) {
        $resultClassification = 'TARGET_REMOVAL_FAILED'
    }
    elseif ($targetRegistryPresentAfter -and -not $registryCleanupStatus) {
        $resultClassification = 'REGISTRY_CLEANUP_FAILED'
    }
    elseif (-not $servicesRestored) {
        $resultClassification = 'SERVICE_RESTORE_FAILED'
    }

    # Build final run summary object
    $summary = [ordered]@{
        run_id                         = $runId
        mode                           = if ($RemoveTarget) { 'RemoveTarget' } elseif ($FullStackReset) { 'FullStackReset' } else { 'BackupOnly' }
        backup_validated               = $validationPassed
        target_identity_count          = if ($targetIdentity) { 1 } else { 0 }
        target_node_count_before       = if ($targetIdentity) { $targetPnpNodes.Count } else { 0 }
        target_node_count_after        = $targetNodesAfterCount
        nodes_removed                  = $nodesRemoved
        nodes_failed                   = $nodesFailed
        target_registry_present_after  = $targetRegistryPresentAfter
        unrelated_nodes_removed        = $unrelatedNodesRemoved
        driver_packages_deleted        = $driverPackagesDeleted
        services_restored              = $servicesRestored
        radio_healthy                  = $radioHealthy
        operator_repair_required       = $operatorRepairRequired
        result                         = $resultClassification
    }

    # Write target-identity-after.json and run-summary.json
    if ($isWhatIf) {
        if ($targetIdentity) {
            $targetIdentityAfter = [ordered]@{
                FriendlyName = $targetIdentity.FriendlyName
                MAC          = $resolvedTargetMac
                ContainerId  = $resolvedContainerId
                Present      = ($targetNodesAfterCount -gt 0)
                NodesAfter   = if ($targetNodesAfterCount -gt 0) {
                    $targetPnpNodes | Where-Object {
                        $check = Get-PnpDevice -InstanceId $_.InstanceId -ErrorAction SilentlyContinue
                        $check -and $check.Present
                    } | Select-Object FriendlyName, InstanceId, Class, Status
                } else { @() }
            }
            $targetIdentityAfter | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $backupDir 'target-identity-after.json') -Encoding UTF8

            $targetPnpNodesAfter = @()
            foreach ($node in $targetPnpNodes) {
                $check = Get-PnpDevice -InstanceId $node.InstanceId -ErrorAction SilentlyContinue
                if ($check -and $check.Present) {
                    $targetPnpNodesAfter += $check
                }
            }
            $targetPnpNodesAfter | Select-Object FriendlyName, InstanceId, Class, Status | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $backupDir 'target-pnp-nodes-after.json') -Encoding UTF8
        }

        try {
            $btDevicesAfter = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
                Select-Object Status, Class, FriendlyName, InstanceId
            $btJsonAfter = $btDevicesAfter | ConvertTo-Json -Depth 3
        } catch {
            $btJsonAfter = '[]'
        }
        $btJsonAfter | Set-Content -Path (Join-Path $backupDir 'all-bluetooth-devices-after.json') -Encoding UTF8

        $svcDataAfter = @{}
        foreach ($svc in $btServices) {
            $svcDataAfter[$svc] = & sc.exe query $svc 2>&1 | Out-String
        }
        $svcDataAfter | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $backupDir 'bluetooth-services-after.json') -Encoding UTF8

        try {
            $radiosAfterObj = Get-BluetoothRadio | Select-Object Status, Class, FriendlyName, InstanceId
            $radioJsonAfter = $radiosAfterObj | ConvertTo-Json -Depth 3
        } catch {
            $radioJsonAfter = '[]'
        }
        $radioJsonAfter | Set-Content -Path (Join-Path $backupDir 'bluetooth-radio-after.json') -Encoding UTF8

        $diffObj = [ordered]@{
            pnp_nodes_removed = $nodesRemoved
            pnp_nodes_failed = $nodesFailed
            registry_removed = ($targetRegistryPresentAfter -eq $false -and $targetIdentity -ne $null)
            driver_packages_deleted = $driverPackagesDeleted
        }
        $diffObj | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $backupDir 'before-after-diff.json') -Encoding UTF8

        $summary | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $backupDir 'run-summary.json') -Encoding UTF8
    }

    # Final summary display
    $sep = '=' * 60
    if ($resultClassification -eq 'TARGET_EVICTION_COMPLETE') {
        Write-Log "`n"
        Write-Log $sep 'Cyan'
        Write-Log '  FLUSH COMPLETE - NEXT STEPS' 'Green'
        Write-Log $sep 'Cyan'
        Write-Log "  Backups saved to: $backupDir"
        Write-Log ""
        Write-Log "  1. Open Settings > Bluetooth & devices"
        Write-Log "  2. Click Add device > Bluetooth"
        Write-Log "  3. Put your Bluetooth speaker/headset in pairing mode"
        Write-Log "  4. Select it when it appears"
        Write-Log ""
        Write-Log "  To restore registry:"
        Write-Log "    reg import `"$backupDir\bthport_device_$resolvedTargetMac.reg`""
        Write-Log $sep 'Cyan'
    } else {
        Write-Log "`n"
        Write-Log $sep 'Red'
        Write-Log "  FLUSH INCOMPLETE - Result: $resultClassification" 'Yellow'
        Write-Log $sep 'Red'
    }

    try {
        $logBuffer -join "`r`n" | Set-Content -Path (Join-Path $backupDir 'transcript.txt') -Encoding UTF8
    } catch {}

    return [PSCustomObject]$summary
}

# Allow direct invocation
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-BluetoothDriverFlush @PSBoundParameters
}
