[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ExactName,[string]$DeviceId)
$ErrorActionPreference='Stop'
# Use Windows PowerShell/.NET Framework and an installed Windows SDK only.
# Preparation compiles locally; no software is downloaded or installed.
$run=Join-Path $env:LOCALAPPDATA ('SysAdminSuite\Evidence\Bluetooth\pair-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $run -Force | Out-Null
try {
    Import-Module (Join-Path $PSScriptRoot 'SasBluetoothRuntime.psm1') -Force
    Import-SasBluetoothHelper $run
    $result=[SasBluetoothPairing]::RunExact($ExactName,$DeviceId).GetAwaiter().GetResult()
    [ordered]@{Target=$ExactName;Result=$result;MouseMovementConfirmed=$false;Evidence=$run} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $run 'result.json')
    if($result -notin 'PAIRING_RESULT=Paired','ALREADY_PAIRED'){exit 1}
} catch {
    @{Target=$ExactName;Result='FAILED';Error=$_.Exception.Message} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $run 'result.json')
    exit 1
}
