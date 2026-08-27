$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../recovery/windows/SasWindowsRecovery.Common.psm1') -Force

function Assert-Equal($Expected, $Actual, $Label) {
    if ($Expected -ne $Actual) { throw "$Label: expected '$Expected', got '$Actual'" }
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
Assert-Equal 'identity_unresolved' $r.status 'unresolved identity fails closed'

Assert-Equal 'healthy' (Convert-SasDismHealthState 0) 'DISM healthy enum'
Assert-Equal 'repairable' (Convert-SasDismHealthState 1) 'DISM repairable enum'
Assert-Equal 'non_repairable' (Convert-SasDismHealthState 2) 'DISM non-repairable enum'

$o = Get-SasWindowsIntegrityOutcome -RestoreHealthExitCode 0 -SfcRepairExitCode 0 -DismImageHealthState 1 -SfcVerifyExitCode 0
Assert-Equal 'component_store_not_clean' $o.status 'repairable final state'
$o = Get-SasWindowsIntegrityOutcome -RestoreHealthExitCode 0 -SfcRepairExitCode 0 -DismImageHealthState 0 -SfcVerifyExitCode 0
Assert-Equal 'verification_commands_succeeded' $o.status 'successful final state'

Write-Host 'Windows recovery behavior contracts passed.'
