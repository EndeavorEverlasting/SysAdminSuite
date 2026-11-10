[CmdletBinding()]
param(
    [ValidateSet('Inspect','StartUserService','EnsureServices','RestartAdapter','ReenumerateAdapter')][string]$Action='Inspect',
    [string]$InstanceId,
    [ValidatePattern('^$|^BluetoothUserService_[a-zA-Z0-9]+$')][string]$ServiceName,
    [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'SysAdminSuite\Evidence\Bluetooth')
)
$ErrorActionPreference='Stop'
$run=Join-Path $OutputRoot ((Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $run -Force | Out-Null
function Get-ScreenshotPreference {
    $key=Get-Item -LiteralPath 'HKCU:\Control Panel\Keyboard'
    $exists=$key.GetValueNames() -contains 'PrintScreenKeyForSnippingEnabled'
    [ordered]@{Exists=$exists;Value=if($exists){$key.GetValue('PrintScreenKeyForSnippingEnabled')}else{$null}}
}
function Save-State([string]$Name) {
    [ordered]@{
        At=(Get-Date).ToString('o')
        Devices=@(Get-PnpDevice -PresentOnly | Where-Object {$_.Class -in 'Bluetooth','Mouse','Keyboard'} | Select-Object Status,Class,FriendlyName,InstanceId)
        Services=@(Get-Service bthserv,BluetoothUserService* | Select-Object Name,@{n='Status';e={[string]$_.Status}},@{n='StartType';e={[string]$_.StartType}})
        ScreenshotPreference=Get-ScreenshotPreference
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run ($Name+'.json'))
}
function Invoke-Pnp([string[]]$PnpArguments,[string]$LogName) {
    $output=& "$env:SystemRoot\System32\pnputil.exe" @PnpArguments 2>&1
    $code=$LASTEXITCODE
    $output | Set-Content -LiteralPath (Join-Path $run $LogName)
    if($code -ne 0){throw "PnP action returned $code; inspect $LogName. No automatic reboot or repeat."}
}
$baseline=Get-ScreenshotPreference | ConvertTo-Json -Compress
$failure=$null
$requiresElevation=$false
try {
    Save-State 'before'
    if($Action -in 'RestartAdapter','ReenumerateAdapter') {
        $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if(-not $admin){$requiresElevation=$true;throw 'REQUIRES_ELEVATION: adapter repair requires an administrator. No UAC setting is changed.'}
    }
    if($Action -in 'StartUserService','EnsureServices') {
        $services=@(Get-Service BluetoothUserService_* -ErrorAction Stop)
        if($ServiceName){$services=@($services|Where-Object {$_.Name -eq $ServiceName})}
        if($services.Count -ne 1){throw 'Expected one per-user Bluetooth service. Multiple sessions require explicit diagnosis.'}
        if($Action -eq 'EnsureServices'){$services=@(Get-Service -Name bthserv -ErrorAction Stop)+$services}
        if(@($services|Where-Object {$_.StartType -eq 'Disabled'}).Count){throw 'Service is disabled. Establish policy ownership before changing startup configuration.'}
        foreach($service in $services) {
        if($service.Status -ne 'Running') {
            # Attempt the service operation with existing rights. Delegated users
            # need not elevate; access denial is reported rather than bypassed.
            try {
                Start-Service -Name $service.Name -ErrorAction Stop
                $service.WaitForStatus('Running',[timespan]::FromSeconds(15))
            } catch {
                $exception=$_.Exception
                while($exception) {
                    if($exception -is [UnauthorizedAccessException] -or ($exception -is [ComponentModel.Win32Exception] -and $exception.NativeErrorCode -eq 5)){$requiresElevation=$true}
                    $exception=$exception.InnerException
                }
                if($_.CategoryInfo.Category -eq 'PermissionDenied'){$requiresElevation=$true}
                throw
            }
        }
        }
    }
    if($Action -in 'RestartAdapter','ReenumerateAdapter') {
        if([string]::IsNullOrWhiteSpace($InstanceId)){throw 'An exact inspected adapter InstanceId is required.'}
        $target=@(Get-PnpDevice -PresentOnly -Class Bluetooth | Where-Object {$_.InstanceId -eq $InstanceId -and $_.InstanceId -like 'USB\*'})
        if($target.Count -ne 1){throw 'Target must match exactly one present USB Bluetooth radio.'}
        if($Action -eq 'RestartAdapter') {
            Invoke-Pnp @('/restart-device',$InstanceId) 'restart.txt'
        } else {
            $inf=(Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName DEVPKEY_Device_DriverInfPath).Data
            if($inf -notmatch '^oem\d+\.inf$'){throw 'No exportable third-party driver package proven; stop before removal.'}
            $backup=Join-Path $run 'driver-backup'
            New-Item -ItemType Directory -Path $backup | Out-Null
            Invoke-Pnp @('/export-driver',$inf,$backup) 'export.txt'
            if(-not @(Get-ChildItem -LiteralPath $backup -Recurse -Filter '*.inf').Count){throw 'Driver export not verified.'}
            # Remove only the selected radio node; preserve its driver package and pairing records.
            try { Invoke-Pnp @('/remove-device',$InstanceId) 'remove.txt' }
            finally { Invoke-Pnp @('/scan-devices') 'scan.txt' }
        }
    }
} catch { $failure=$_.Exception.Message }
finally {
    try {
        Save-State 'after'
        if((Get-ScreenshotPreference | ConvertTo-Json -Compress) -ne $baseline){$failure='REGRESSION: screenshot preference changed during recovery.'}
    } catch { $failure='After-state verification failed: '+$_.Exception.Message }
    [ordered]@{Action=$Action;Status=if($requiresElevation){'REQUIRES_ELEVATION'}elseif($failure){'FAILED'}else{'ACTION_COMPLETE_PHYSICAL_TEST_PENDING'};RequiresElevation=$requiresElevation;Error=$failure;Evidence=$run;MouseVerified=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'result.json')
}
Get-Content -LiteralPath (Join-Path $run 'result.json')
if($failure){exit 1}
