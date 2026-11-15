[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('capabilities','inspect','list','profile-save','profile-list','restore','watch','pair','ensure-service','restart','reenumerate','prepare')][string]$Command='capabilities',
    [string]$ExactName,[string]$DeviceId,[string]$ServiceName,[string]$InstanceId,[string]$Destination,
    [ValidateRange(10,3600)][int]$IntervalSeconds=30
)
$ErrorActionPreference='Stop'
function Invoke-SasBluetoothProfileCommand {
    Import-Module (Join-Path $PSScriptRoot 'SasBluetoothProfile.psm1') -Force
    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not $localData) { throw 'LOCAL_USER_PROFILE_REQUIRED' }
    $profileRoot = Join-Path $localData 'SysAdminSuite\Bluetooth'
    $profilePath = Join-Path $profileRoot 'device-profile.json'

    if ($Command -eq 'profile-list') {
        ConvertTo-Json -InputObject @(Read-SasBluetoothProfile $profilePath) -Depth 5
        return
    }
    if ([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
        throw 'INTERACTIVE_USER_SESSION_REQUIRED'
    }
    if ($Command -eq 'profile-save') {
        if ($ExactName) { throw 'PROFILE_SAVE_USE_DEVICE_ID_OR_CAPTURE_ALL' }
        $null = New-Item -ItemType Directory -Path $profileRoot -Force
        $run = Join-Path $localData ('SysAdminSuite\Evidence\Bluetooth\capture-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $run -Force
        Import-SasBluetoothHelper $run
        $mappings = [SasBluetoothPairing]::List().GetAwaiter().GetResult()
        Save-SasBluetoothProfile $profilePath $mappings $DeviceId | ConvertTo-Json -Depth 5
        return
    }

    $device = Select-SasBluetoothProfileDevice @(Read-SasBluetoothProfile $profilePath) $DeviceId $ExactName
    $run = Join-Path $localData ('SysAdminSuite\Evidence\Bluetooth\' + $Command + '-' + [guid]::NewGuid().ToString('N'))
    try {
        # Keep a one-shot restore from racing a running watch in this user profile.
        $lock = [IO.File]::Open((Join-Path $profileRoot 'recovery.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    } catch [IO.IOException] {
        throw 'BLUETOOTH_RECOVERY_LOCK_UNAVAILABLE: stop the other restore or watch and try again.'
    }
    try {
        $null = New-Item -ItemType Directory -Path $run -Force
        Import-SasBluetoothHelper $run
        $observe = { param($id) [SasBluetoothPairing]::Observe($id).GetAwaiter().GetResult() }
        $reconnect = { param($id) [SasBluetoothPairing]::Reconnect($id).GetAwaiter().GetResult() }
        $pair = { param($id) [SasBluetoothPairing]::PairSaved($id).GetAwaiter().GetResult() }
        $lastStatus = $null
        do {
            $result = Invoke-SasBluetoothSavedDevice $device ($Command -eq 'restore') $observe $reconnect $pair
            # Record state changes and actual attempts, without retaining idle polls.
            if ($result.Status -ne $lastStatus -or $result.Action -in 'PAIR', 'RECONNECT') {
                $result | Add-Member -NotePropertyName Evidence -NotePropertyValue $run
                $json = ConvertTo-Json -InputObject $result -Depth 5 -Compress
                Add-Content -LiteralPath (Join-Path $run 'results.jsonl') -Value $json -Encoding UTF8
                $json
            }
            $lastStatus = $result.Status
            if ($Command -eq 'restore') {
                if ($lastStatus -notin 'ALREADY_CONNECTED','CONNECTED_OBSERVED') { exit 2 }
                return
            }
            Start-Sleep -Seconds $IntervalSeconds
        } while ($true)
    } finally {
        $lock.Dispose()
    }
}

try {
    Import-Module (Join-Path $PSScriptRoot 'SasBluetoothRuntime.psm1') -Force
    $root=Split-Path $PSScriptRoot -Parent
    if(Test-Path -LiteralPath (Join-Path $root 'bluetooth-bundle.json')){$null=Test-SasBluetoothBundle $root}
    if ($Command -in 'profile-save','profile-list','restore','watch') {
        Invoke-SasBluetoothProfileCommand
        exit 0
    }
    switch($Command) {
        'capabilities' {Get-SasBluetoothCapabilities | ConvertTo-Json -Depth 5}
        'prepare' {& (Join-Path $PSScriptRoot 'Prepare-BluetoothPeripheralBundle.ps1') -Destination $Destination; exit $LASTEXITCODE}
        'pair' {
            if([string]::IsNullOrWhiteSpace($ExactName)){throw 'EXACT_DEVICE_NAME_REQUIRED'}
            $states=@(Get-Service bthserv,BluetoothUserService_* -ErrorAction Stop)
            $userServices=@($states|Where-Object {$_.Name -like 'BluetoothUserService_*'})
            if($ServiceName){$userServices=@($userServices|Where-Object {$_.Name -eq $ServiceName})}
            if($userServices.Count -ne 1){throw 'EXACT_USER_SERVICE_REQUIRED: select the intended signed-in user service using -ServiceName.'}
            $selected=@($states|Where-Object {$_.Name -eq 'bthserv'})+$userServices
            if(@($selected|Where-Object {$_.Status -ne 'Running'}).Count) {
                & (Join-Path $PSScriptRoot 'Invoke-BluetoothPeripheralRecovery.ps1') -Action EnsureServices -ServiceName $ServiceName
                if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
            }
            & (Join-Path $PSScriptRoot 'Add-BluetoothMouse.ps1') -ExactName $ExactName -DeviceId $DeviceId
            exit $LASTEXITCODE
        }
        'list' {
            $run=Join-Path $env:LOCALAPPDATA ('SysAdminSuite\Evidence\Bluetooth\list-'+[guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $run -Force | Out-Null
            Import-SasBluetoothHelper $run
            $mappings=[SasBluetoothPairing]::List().GetAwaiter().GetResult()
            ConvertTo-Json -InputObject @($mappings) -Depth 5 | Tee-Object -FilePath (Join-Path $run 'mappings.json')
        }
        default {
            $actions=@{inspect='Inspect';'ensure-service'='EnsureServices';restart='RestartAdapter';reenumerate='ReenumerateAdapter'}
            & (Join-Path $PSScriptRoot 'Invoke-BluetoothPeripheralRecovery.ps1') -Action $actions[$Command] -InstanceId $InstanceId -ServiceName $ServiceName
            exit $LASTEXITCODE
        }
    }
} catch {
    @{Status='UNAVAILABLE';Error=$_.Exception.Message;SecurityPolicyChanged=$false} | ConvertTo-Json
    exit 1
}
