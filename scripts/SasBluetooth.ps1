[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('capabilities','inspect','list','pair','ensure-service','restart','reenumerate','prepare')][string]$Command='capabilities',
    [string]$ExactName,[string]$DeviceId,[string]$ServiceName,[string]$InstanceId,[string]$Destination
)
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'SasBluetoothRuntime.psm1') -Force
    $root=Split-Path $PSScriptRoot -Parent
    if(Test-Path -LiteralPath (Join-Path $root 'bluetooth-bundle.json')){$null=Test-SasBluetoothBundle $root}
    switch($Command) {
        'capabilities' {Get-SasBluetoothCapabilities | ConvertTo-Json -Depth 5}
        'prepare' {& (Join-Path $PSScriptRoot 'Prepare-BluetoothPeripheralBundle.ps1') -Destination $Destination; exit $LASTEXITCODE}
        'pair' {& (Join-Path $PSScriptRoot 'Add-BluetoothMouse.ps1') -ExactName $ExactName -DeviceId $DeviceId; exit $LASTEXITCODE}
        'list' {
            $run=Join-Path $env:LOCALAPPDATA ('SysAdminSuite\Evidence\Bluetooth\list-'+[guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $run -Force | Out-Null
            Import-SasBluetoothHelper $run
            $mappings=[SasBluetoothPairing]::List().GetAwaiter().GetResult()
            ConvertTo-Json -InputObject @($mappings) -Depth 5 | Tee-Object -FilePath (Join-Path $run 'mappings.json')
        }
        default {
            $actions=@{inspect='Inspect';'ensure-service'='StartUserService';restart='RestartAdapter';reenumerate='ReenumerateAdapter'}
            & (Join-Path $PSScriptRoot 'Invoke-BluetoothPeripheralRecovery.ps1') -Action $actions[$Command] -InstanceId $InstanceId -ServiceName $ServiceName
            exit $LASTEXITCODE
        }
    }
} catch {
    @{Status='UNAVAILABLE';Error=$_.Exception.Message;SecurityPolicyChanged=$false} | ConvertTo-Json
    exit 1
}
