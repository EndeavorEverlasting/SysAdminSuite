Set-StrictMode -Version Latest

function Invoke-SasNativeCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @()
    )

    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 can promote redirected native stderr into
        # PowerShell's error stream. Keep that behavior local so stderr is
        # captured as evidence and the native exit code remains observable.
        $ErrorActionPreference = 'Continue'
        $lines = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    [pscustomobject]@{
        exit_code = $code
        output = $lines
    }
}

function Test-SasBackupTargetIdentity {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()]$SystemVolume,
        [Parameter()][AllowNull()]$TargetVolume,
        [string]$ExpectedLabel,
        [string]$ExpectedBusType,
        [string]$ExpectedDiskModel
    )

    $systemDisk = if ($null -ne $SystemVolume) { $SystemVolume.disk_number } else { $null }
    $targetDisk = if ($null -ne $TargetVolume) { $TargetVolume.disk_number } else { $null }
    $resolved = $null -ne $systemDisk -and $null -ne $targetDisk
    $sameDisk = $resolved -and $systemDisk -eq $targetDisk
    $labelMatch = $null -ne $TargetVolume -and (-not $ExpectedLabel -or $TargetVolume.label -eq $ExpectedLabel)
    $busMatch = $null -ne $TargetVolume -and (-not $ExpectedBusType -or $TargetVolume.bus_type -eq $ExpectedBusType)
    $modelMatch = $null -ne $TargetVolume -and (-not $ExpectedDiskModel -or $TargetVolume.disk_model -eq $ExpectedDiskModel)
    $pinned = [bool]($ExpectedLabel -or $ExpectedBusType -or $ExpectedDiskModel)

    $status = if ($null -eq $TargetVolume) { 'target_not_mounted' }
    elseif (-not $resolved) { 'identity_unresolved' }
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

function Get-SasDeepStoragePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z]:\\?$')][string]$SystemDrive,
        [Parameter(Mandatory)][string]$UserProfile
    )

    $root = $SystemDrive.Substring(0, 1).ToUpperInvariant() + ':\'
    @(
        "${root}Users",
        "${root}Windows",
        "${root}Program Files",
        "${root}Program Files (x86)",
        "${root}ProgramData",
        "${root}`$Recycle.Bin",
        (Join-Path $UserProfile 'Downloads'),
        (Join-Path $UserProfile 'Desktop'),
        (Join-Path $UserProfile 'Documents'),
        (Join-Path $UserProfile 'AppData\Local\Temp'),
        (Join-Path $UserProfile 'AppData\Local\Docker'),
        (Join-Path $UserProfile '.cache')
    ) | Select-Object -Unique
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

Export-ModuleMember -Function Invoke-SasNativeCapture, Test-SasBackupTargetIdentity, Get-SasDeepStoragePaths, Convert-SasDismHealthState, Get-SasWindowsIntegrityOutcome
