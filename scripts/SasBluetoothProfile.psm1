Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-SasBluetoothProfile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $profile = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    if ($profile.Schema -cne 'sas-bluetooth-device-profile/v1' -or $profile.Devices -isnot [array]) {
        throw 'INVALID_BLUETOOTH_PROFILE'
    }
    $devices = @{}
    foreach ($device in $profile.Devices) {
        if ($device.DeviceId -isnot [string] -or [string]::IsNullOrWhiteSpace($device.DeviceId) -or
            $device.Name -isnot [string] -or $devices.ContainsKey($device.DeviceId)) {
            throw 'INVALID_BLUETOOTH_PROFILE_DEVICE'
        }
        $devices[$device.DeviceId] = $device
        $device
    }
}

function Save-SasBluetoothProfile([string]$Path, [object[]]$Observed, [string]$DeviceId) {
    $paired = @($Observed | Where-Object { $_.Paired -and (-not $DeviceId -or $_.DeviceId -eq $DeviceId) })
    if (-not $paired.Count) { throw 'NO_MATCHING_PAIRED_BLUETOOTH_DEVICE' }

    # Serialize read/merge/replace so a concurrent capture cannot lose a saved endpoint.
    $lock = [IO.File]::Open("$Path.lock", 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        $devices = @{}
        foreach ($device in @(Read-SasBluetoothProfile $Path)) { $devices[$device.DeviceId] = $device }
        foreach ($device in $paired) {
            $devices[$device.DeviceId] = [pscustomobject]@{ DeviceId = [string]$device.DeviceId; Name = [string]$device.Name }
        }
        $profile = [ordered]@{
            Schema = 'sas-bluetooth-device-profile/v1'
            Devices = @($devices.Values | Sort-Object DeviceId)
        }
        $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
        $backup = "$temp.bak"
        try {
            $profile | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temp -Encoding UTF8
            if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, $backup) }
            else { [IO.File]::Move($temp, $Path) }
        } finally {
            [IO.File]::Delete($temp)
            [IO.File]::Delete($backup)
        }
        [pscustomobject]@{ Status = 'PROFILE_SAVED'; SavedCount = $paired.Count; ProfileCount = $devices.Count }
    } finally {
        $lock.Dispose()
    }
}

function Select-SasBluetoothProfileDevice([object[]]$Devices, [string]$DeviceId, [string]$ExactName) {
    if (-not $DeviceId -and -not $ExactName) { throw 'SAVED_DEVICE_ID_OR_EXACT_NAME_REQUIRED' }
    $matches = @($Devices | Where-Object {
        (-not $DeviceId -or $_.DeviceId -eq $DeviceId) -and (-not $ExactName -or $_.Name -ceq $ExactName)
    })
    if (-not $matches.Count) { throw 'DEVICE_NOT_IN_BLUETOOTH_PROFILE' }
    if ($matches.Count -ne 1) { throw 'AMBIGUOUS_SAVED_NAME_USE_DEVICE_ID' }
    $matches[0]
}

function Get-SasBluetoothRestoreDecision($Endpoint, [bool]$ExplicitRestore) {
    if ($null -eq $Endpoint) { return 'SAVED_ENDPOINT_NOT_OBSERVED' }
    if ($Endpoint.Paired -and $Endpoint.Connected -eq $true) { return 'ALREADY_CONNECTED' }
    if ($Endpoint.Paired -and ($ExplicitRestore -or $Endpoint.Present -eq $true)) { return 'RECONNECT' }
    if ($Endpoint.Paired) { return 'WAITING_FOR_DEVICE' }
    if ($ExplicitRestore -and $Endpoint.Present -eq $true -and $Endpoint.CanPair) { return 'PAIR' }
    if ($ExplicitRestore -and $Endpoint.Present -ne $true) { return 'WAITING_FOR_DEVICE' }
    'WINDOWS_PAIRING_REQUIRED'
}

function Invoke-SasBluetoothSavedDevice {
    param($Device, [bool]$ExplicitRestore, [scriptblock]$Observe, [scriptblock]$Reconnect, [scriptblock]$Pair)

    $before = $null
    $after = $null
    $decision = 'OBSERVE'
    $nativeResult = $null
    $status = 'OBSERVATION_FAILED'
    $failure = $null
    try {
        $before = & $Observe $Device.DeviceId
        if ($null -ne $before -and $before.DeviceId -ne $Device.DeviceId) { throw 'BLUETOOTH_OBSERVATION_ID_MISMATCH' }
        $decision = Get-SasBluetoothRestoreDecision $before $ExplicitRestore
        $status = $decision
        if ($decision -in 'RECONNECT', 'PAIR') {
            $status = 'ATTEMPT_FAILED'
            if ($decision -eq 'PAIR') { $nativeResult = & $Pair $before.DeviceId }
            else { $nativeResult = & $Reconnect $before.DeviceId }
            $status = 'POST_ATTEMPT_OBSERVATION_FAILED'
            $after = & $Observe $Device.DeviceId
            if ($null -ne $after -and $after.DeviceId -ne $Device.DeviceId) { throw 'BLUETOOTH_OBSERVATION_ID_MISMATCH' }
            $status = 'CONNECTION_NOT_OBSERVED'
            if ($null -ne $after -and $after.Paired -and $after.Connected -eq $true) {
                $status = 'CONNECTED_OBSERVED'
            } elseif ($decision -eq 'PAIR' -and $null -ne $after -and $after.Paired) {
                $status = 'PAIRED_CONNECTION_NOT_OBSERVED'
            }
        }
    } catch {
        $failure = $_.Exception.Message
    }
    [pscustomobject]@{
        Schema = 'sas-bluetooth-restore/v1'
        TimestampUtc = [DateTime]::UtcNow.ToString('o')
        DeviceId = $Device.DeviceId
        Name = $Device.Name
        Status = $status
        Action = $decision
        NativeResult = $nativeResult
        Before = $before
        After = $after
        Error = $failure
    }
}

Export-ModuleMember -Function Invoke-SasBluetoothSavedDevice, Read-SasBluetoothProfile, Save-SasBluetoothProfile, Select-SasBluetoothProfileDevice, Get-SasBluetoothRestoreDecision
