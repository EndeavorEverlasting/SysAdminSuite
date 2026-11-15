$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $root 'scripts/SasBluetoothProfile.psm1') -Force
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('sas-bluetooth-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $fixture
$profile = Join-Path $fixture 'profile.json'

function Assert-Equal($Actual, $Expected) {
    if ($Actual -cne $Expected) { throw "Expected [$Expected], observed [$Actual]" }
}

try {
    $one = [pscustomobject]@{ DeviceId = 'synthetic-one'; Name = 'Mouse'; Paired = $true }
    $two = [pscustomobject]@{ DeviceId = 'synthetic-two'; Name = 'Mouse'; Paired = $true }
    $other = [pscustomobject]@{ DeviceId = 'synthetic-nearby'; Name = 'Mouse'; Paired = $false }
    Assert-Equal @(Read-SasBluetoothProfile $profile).Count 0
    Assert-Equal (Save-SasBluetoothProfile $profile @($one, $two, $other)).SavedCount 2
    Assert-Equal @(Read-SasBluetoothProfile $profile).Count 2
    Assert-Equal (Save-SasBluetoothProfile $profile @($one) $one.DeviceId).ProfileCount 2
    $devices = @(Read-SasBluetoothProfile $profile)
    try {
        $null = Select-SasBluetoothProfileDevice $devices -ExactName 'Mouse'
        throw 'Expected ambiguous name'
    } catch {
        Assert-Equal $_.Exception.Message 'AMBIGUOUS_SAVED_NAME_USE_DEVICE_ID'
    }
    $selected = Select-SasBluetoothProfileDevice $devices $two.DeviceId
    Assert-Equal $selected.DeviceId $two.DeviceId

    $state = @{ Paired = $true; Present = $true; Connected = $true; LinkOnReconnect = $true
        PairCalls = 0; ReconnectCalls = 0; ObserveCalls = 0; PostFailure = $false; WrongId = $false; Missing = $false }
    $observe = {
        param($id)
        Assert-Equal $id $selected.DeviceId
        $state.ObserveCalls++
        if ($state.Missing) { return }
        if ($state.PostFailure -and $state.ObserveCalls -gt 1) { throw 'fixture observation failed' }
        [pscustomobject]@{
            DeviceId = if ($state.WrongId) { $one.DeviceId } else { $id }
            Paired = $state.Paired; CanPair = $true; Present = $state.Present; Connected = $state.Connected
        }
    }
    $reconnect = {
        param($id)
        Assert-Equal $id $selected.DeviceId
        $state.ReconnectCalls++
        $state.Connected = $state.LinkOnReconnect
        'GATT_DISCOVERY=Success'
    }
    $pair = {
        param($id)
        Assert-Equal $id $selected.DeviceId
        $state.PairCalls++
        $state.Paired = $true
        'PAIRING_RESULT=Paired'
    }
    function Assert-Outcome($Expected, [bool]$Explicit) {
        $receipt = Invoke-SasBluetoothSavedDevice $selected $Explicit $observe $reconnect $pair
        Assert-Equal $receipt.Status $Expected
        Assert-Equal $receipt.DeviceId $selected.DeviceId
    }

    Assert-Outcome 'ALREADY_CONNECTED' $false
    $state.Connected = $false
    $state.Present = $false
    Assert-Outcome 'WAITING_FOR_DEVICE' $false
    Assert-Equal $state.ReconnectCalls 0
    $state.Present = $true
    Assert-Outcome 'CONNECTED_OBSERVED' $false
    Assert-Equal $state.ReconnectCalls 1
    $state.Connected = $false
    $state.LinkOnReconnect = $false
    Assert-Outcome 'CONNECTION_NOT_OBSERVED' $true
    $state.Paired = $false
    Assert-Outcome 'WINDOWS_PAIRING_REQUIRED' $false
    Assert-Equal $state.PairCalls 0
    Assert-Outcome 'PAIRED_CONNECTION_NOT_OBSERVED' $true
    Assert-Equal $state.PairCalls 1
    $state.PostFailure = $true
    $state.ObserveCalls = 0
    Assert-Outcome 'POST_ATTEMPT_OBSERVATION_FAILED' $true
    $state.PostFailure = $false
    $state.WrongId = $true
    Assert-Outcome 'OBSERVATION_FAILED' $true
    $state.WrongId = $false
    $state.Missing = $true
    Assert-Outcome 'SAVED_ENDPOINT_NOT_OBSERVED' $true
    Assert-Equal $state.ReconnectCalls 3

    $before = [IO.File]::ReadAllText($profile)
    $lock = [IO.File]::Open("$profile.lock", 'Open', 'ReadWrite', 'None')
    try {
        try {
            $null = Save-SasBluetoothProfile $profile @($one)
            throw 'Expected writer exclusion'
        } catch {
            if ($_.Exception.Message -eq 'Expected writer exclusion') { throw }
        }
        Assert-Equal ([IO.File]::ReadAllText($profile)) $before
    } finally {
        $lock.Dispose()
    }

    [IO.File]::WriteAllText($profile, '{"Schema":"invalid","Devices":[]}')
    try {
        $null = Save-SasBluetoothProfile $profile @($one)
        throw 'Expected corrupt profile rejection'
    } catch {
        Assert-Equal $_.Exception.Message 'INVALID_BLUETOOTH_PROFILE'
    }
    Assert-Equal ([IO.File]::ReadAllText($profile)) '{"Schema":"invalid","Devices":[]}'
    'PASS: saved-device profile and recovery fixtures'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
