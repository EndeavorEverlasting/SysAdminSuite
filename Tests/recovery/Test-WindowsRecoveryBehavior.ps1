Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../recovery/windows/SasWindowsRecovery.Common.psm1') -Force

function Assert-Equal($Expected, $Actual, $Label) {
    if ($Expected -ne $Actual) { throw "$Label: expected '$Expected', got '$Actual'" }
}

function Assert-True($Actual, $Label) {
    if (-not $Actual) { throw "$Label: expected true" }
}

$system = [pscustomobject]@{ disk_number = 0; label = 'OS'; bus_type = 'NVMe'; disk_model = 'System NVMe' }
$target = [pscustomobject]@{ disk_number = 1; label = 'LaptopBackup'; bus_type = 'USB'; disk_model = 'USB Bridge' }
$same = [pscustomobject]@{ disk_number = 0; label = 'Other'; bus_type = 'NVMe'; disk_model = 'System NVMe' }
$unknown = [pscustomobject]@{ disk_number = $null; label = 'LaptopBackup'; bus_type = 'USB'; disk_model = 'USB Bridge' }

$r = Test-SasBackupTargetIdentity -SystemVolume $system -TargetVolume $target -ExpectedLabel 'LaptopBackup' -ExpectedBusType 'USB'
Assert-Equal 'safe_pinned' $r.status 'pinned target'
Assert-Equal $true $r.distinct_physical_disk 'physical separation'

$r = Test-SasBackupTargetIdentity -SystemVolume $system -TargetVolume $same
Assert-Equal 'unsafe_same_physical_disk' $r.status 'same-disk rejection'
$r = Test-SasBackupTargetIdentity -SystemVolume $system -TargetVolume $target -ExpectedLabel 'WrongLabel'
Assert-Equal 'identity_mismatch' $r.status 'label mismatch'
$r = Test-SasBackupTargetIdentity -SystemVolume $system -TargetVolume $unknown
Assert-Equal 'identity_unresolved' $r.status 'unresolved target identity fails closed'
$r = Test-SasBackupTargetIdentity -SystemVolume $null -TargetVolume $target
Assert-Equal 'identity_unresolved' $r.status 'missing system mapping degrades without throwing'
Assert-Equal $null $r.system_disk_number 'missing system mapping preserves null disk number'
$r = Test-SasBackupTargetIdentity -SystemVolume $system -TargetVolume $null
Assert-Equal 'target_not_mounted' $r.status 'missing target fails closed'

$paths = @(Get-SasDeepStoragePaths -SystemDrive 'X:' -UserProfile 'X:\Users\FixtureUser')
Assert-True ($paths -contains 'X:\Windows') 'system-drive Windows path'
Assert-True ($paths -contains 'X:\Users') 'system-drive Users path'
Assert-Equal $false (@($paths | Where-Object { $_ -like 'C:\*' }).Count -gt 0) 'non-C drive must not emit C paths'

Assert-Equal 'healthy' (Convert-SasDismHealthState 0) 'DISM healthy enum'
Assert-Equal 'repairable' (Convert-SasDismHealthState 1) 'DISM repairable enum'
Assert-Equal 'non_repairable' (Convert-SasDismHealthState 2) 'DISM non-repairable enum'
Assert-Equal 'unknown' (Convert-SasDismHealthState 99) 'DISM unknown enum'

$o = Get-SasWindowsIntegrityOutcome -RestoreHealthExitCode 0 -SfcRepairExitCode 0 -DismImageHealthState 1 -SfcVerifyExitCode 0
Assert-Equal 'component_store_not_clean' $o.status 'repairable final state'
$o = Get-SasWindowsIntegrityOutcome -RestoreHealthExitCode 0 -SfcRepairExitCode 0 -DismImageHealthState 0 -SfcVerifyExitCode 0
Assert-Equal 'verification_commands_succeeded' $o.status 'successful final command state'
Assert-Equal 'raw_output_captured_not_locale_normalized' $o.sfc_semantic_proof 'SFC proof ceiling stays honest'

if ($env:OS -eq 'Windows_NT') {
    $native = Invoke-SasNativeCapture -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', 'echo fixture-error 1>&2 & exit /b 7')
}
else {
    $native = Invoke-SasNativeCapture -FilePath '/bin/sh' -ArgumentList @('-c', 'echo fixture-error >&2; exit 7')
}
Assert-Equal 7 $native.exit_code 'native stderr command exit code'
Assert-True ((@($native.output) -join "`n") -match 'fixture-error') 'native stderr remains captured'

Write-Host 'Windows recovery behavior contracts passed.'
