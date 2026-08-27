Set-StrictMode -Version Latest

function Test-SasBackupTargetIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$SystemVolume,
        [Parameter(Mandatory)]$TargetVolume,
        [string]$ExpectedLabel,
        [string]$ExpectedBusType,
        [string]$ExpectedDiskModel
    )

    $systemDisk = $SystemVolume.disk_number
    $targetDisk = $TargetVolume.disk_number
    $resolved = $null -ne $systemDisk -and $null -ne $targetDisk
    $sameDisk = $resolved -and $systemDisk -eq $targetDisk
    $labelMatch = -not $ExpectedLabel -or $TargetVolume.label -eq $ExpectedLabel
    $busMatch = -not $ExpectedBusType -or $TargetVolume.bus_type -eq $ExpectedBusType
    $modelMatch = -not $ExpectedDiskModel -or $TargetVolume.disk_model -eq $ExpectedDiskModel
    $pinned = [bool]($ExpectedLabel -or $ExpectedBusType -or $ExpectedDiskModel)

    $status = if (-not $resolved) { 'identity_unresolved' }
    elseif ($sameDisk) { 'unsafe_same_physical_disk' }
    elseif (-not ($labelMatch -and $busMatch -and $modelMatch)) { 'identity_mismatch' }
    elseif ($pinned) { 'safe_pinned' }
    else { 'safe_unpinned' }

    [pscustomobject]@{
        status = $status
        system_disk_number = $systemDisk
        target_disk_number = $targetDisk
        distinct_physical_disk = if ($resolved) { -not $sameDisk } else { $null }
        expected_label = $ExpectedLabel
        label_match = $labelMatch
        expected_bus_type = $ExpectedBusType
        bus_type_match = $busMatch
        expected_disk_model = $ExpectedDiskModel
        disk_model_match = $modelMatch
        expectations_pinned = $pinned
    }
}

function Convert-SasDismHealthState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$ImageHealthState)
    switch ($ImageHealthState) {
        0 { 'healthy' }
        1 { 'repairable' }
        2 { 'non_repairable' }
        default { 'unknown' }
    }
}

function Get-SasWindowsIntegrityOutcome {
    [CmdletBinding()]
    param(
        [int]$RestoreHealthExitCode,
        [int]$SfcRepairExitCode,
        [int]$DismImageHealthState,
        [int]$SfcVerifyExitCode
    )

    $dism = Convert-SasDismHealthState -ImageHealthState $DismImageHealthState
    $status = if ($RestoreHealthExitCode -ne 0) { 'restore_health_failed' }
    elseif ($dism -ne 'healthy') { 'component_store_not_clean' }
    elseif ($SfcRepairExitCode -ne 0 -or $SfcVerifyExitCode -ne 0) { 'sfc_command_failed' }
    else { 'verification_commands_succeeded' }

    [pscustomobject]@{
        status = $status
        dism_final_state = $dism
        sfc_final_state = if ($SfcVerifyExitCode -eq 0) { 'verification_command_succeeded' } else { 'verification_command_failed' }
        sfc_semantic_proof = 'raw_output_captured_not_locale_normalized'
    }
}

Export-ModuleMember -Function Test-SasBackupTargetIdentity, Convert-SasDismHealthState, Get-SasWindowsIntegrityOutcome
