[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Destination)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SasBluetoothRuntime.psm1') -Force
$root=Split-Path $PSScriptRoot -Parent
$sourceCommit=$null
if(Test-Path -LiteralPath (Join-Path $root '.git')) {
    $sourceCommit=& git -C $root rev-parse HEAD
    if($LASTEXITCODE -ne 0){throw 'PREPARATION_SOURCE_UNPROVEN'}
    $dirty=& git -C $root status --porcelain --untracked-files=no
    if($LASTEXITCODE -ne 0 -or $dirty){throw 'COMMIT_PREPARATION_SOURCE_FIRST'}
}
if(Test-Path -LiteralPath $Destination){throw 'Destination must be new; existing deployments are never overwritten.'}
$destinationPath=[IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Path $destinationPath -ErrorAction Stop | Out-Null
New-Item -ItemType Directory -Path (Join-Path $destinationPath 'scripts'),(Join-Path $destinationPath 'runtime') | Out-Null
$files=@('SasBluetooth.cmd','Add-BluetoothMouse.cmd','Recover-BluetoothPeripheral.cmd','scripts/SasBluetooth.ps1','scripts/Add-BluetoothMouse.ps1','scripts/Invoke-BluetoothPeripheralRecovery.ps1','scripts/SasBluetoothRuntime.psm1','scripts/SasBluetoothPairing.cs','scripts/Prepare-BluetoothPeripheralBundle.ps1')
foreach($file in $files){Copy-Item -LiteralPath (Join-Path $root $file) -Destination (Join-Path $destinationPath $file)}
$null=New-SasBluetoothHelper (Join-Path $destinationPath 'runtime\SasBluetoothPairing.dll')
$files+='runtime/SasBluetoothPairing.dll'
$hashes=@(foreach($file in $files){@{Path=$file;SHA256=(Get-SasBluetoothHash (Join-Path $destinationPath $file))}})
@{Schema='sas-bluetooth-bundle/v1';SourceCommit=$sourceCommit;PreparedAt=(Get-Date).ToString('o');HostRuntime='Windows 10/11 x64, Windows PowerShell 5.1, approved .NET Framework/WinRT execution';TargetSDKRequired=$false;Files=$hashes} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destinationPath 'bluetooth-bundle.json')
$null=Test-SasBluetoothBundle $destinationPath
@{Status='PREPARED_NOT_TARGET_CERTIFIED';Destination=$destinationPath;EntryPoint='SasBluetooth.cmd';SecurityPolicyChanged=$false} | ConvertTo-Json
