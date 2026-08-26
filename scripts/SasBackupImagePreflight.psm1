Set-StrictMode -Version Latest

function ConvertTo-SasDriveLetter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveLetter
    )

    $normalized = $DriveLetter.Trim().TrimEnd(':').ToUpperInvariant()
    if ($normalized -notmatch '^[A-Z]$') {
        throw "DriveLetter must be a single Windows drive letter. Received: '$DriveLetter'."
    }
    return $normalized
}

function Get-SasBackupImageVolumeRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveLetter
    )

    $letter = ConvertTo-SasDriveLetter -DriveLetter $DriveLetter
    $volume = Get-Volume -DriveLetter $letter -ErrorAction Stop
    $partition = Get-Partition -DriveLetter $letter -ErrorAction Stop
    $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop

    $sizeBytes = [double]$volume.Size
    $freeBytes = [double]$volume.SizeRemaining
    $usedBytes = $sizeBytes - $freeBytes

    [pscustomobject]@{
        DriveLetter             = $letter
        Label                   = [string]$volume.FileSystemLabel
        FileSystem              = [string]$volume.FileSystem
        VolumeHealthStatus      = [string]$volume.HealthStatus
        VolumeOperationalStatus = (@($volume.OperationalStatus) -join ',')
        DiskNumber              = [int]$partition.DiskNumber
        DiskFriendlyName        = [string]$disk.FriendlyName
        DiskHealthStatus        = [string]$disk.HealthStatus
        DiskOperationalStatus   = (@($disk.OperationalStatus) -join ',')
        SizeGB                  = [math]::Round($sizeBytes / 1GB, 2)
        UsedGB                  = [math]::Round($usedBytes / 1GB, 2)
        FreeGB                  = [math]::Round($freeBytes / 1GB, 2)
    }
}

function Test-SasBackupImagePreflightDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Source,

        [Parameter(Mandatory = $true)]
        [psobject]$Target,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedTargetLabel,

        [ValidateRange(1, 1024)]
        [double]$MinimumSourceFreeGB = 20,

        [ValidateRange(0, 1024)]
        [double]$MinimumTargetHeadroomGB = 20,

        [bool]$TargetStabilityPassed = $true
    )

    $reasons = New-Object System.Collections.Generic.List[string]

    if ($Source.DiskNumber -eq $Target.DiskNumber) {
        $reasons.Add('SOURCE_TARGET_SAME_PHYSICAL_DISK')
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedTargetLabel) -or $Target.Label -ne $ExpectedTargetLabel) {
        $reasons.Add('TARGET_LABEL_MISMATCH')
    }
    if ($Target.FileSystem -ne 'NTFS') {
        $reasons.Add('TARGET_FILESYSTEM_NOT_NTFS')
    }
    if ($Target.VolumeHealthStatus -ne 'Healthy' -or $Target.DiskHealthStatus -ne 'Healthy') {
        $reasons.Add('TARGET_HEALTH_NOT_HEALTHY')
    }
    if ($Target.VolumeOperationalStatus -notmatch '(^|,)OK(,|$)' -or $Target.DiskOperationalStatus -notmatch '(^|,)Online(,|$)|(^|,)OK(,|$)') {
        $reasons.Add('TARGET_OPERATIONAL_STATUS_NOT_OK')
    }
    if ($Source.VolumeHealthStatus -ne 'Healthy' -or $Source.DiskHealthStatus -ne 'Healthy') {
        $reasons.Add('SOURCE_HEALTH_NOT_HEALTHY')
    }
    if (-not $TargetStabilityPassed) {
        $reasons.Add('TARGET_CONNECTION_NOT_STABLE')
    }
    if ([double]$Source.FreeGB -lt $MinimumSourceFreeGB) {
        $reasons.Add('SOURCE_FREE_SPACE_BELOW_MINIMUM')
    }

    $rawHeadroomGB = [math]::Round(([double]$Target.FreeGB - [double]$Source.UsedGB), 2)
    if ($rawHeadroomGB -lt $MinimumTargetHeadroomGB) {
        $reasons.Add('TARGET_RAW_CAPACITY_HEADROOM_BELOW_MINIMUM')
    }

    [pscustomobject]@{
        Decision                = $(if ($reasons.Count -eq 0) { 'READY' } else { 'BLOCKED' })
        Reasons                 = @($reasons)
        RawCapacityHeadroomGB   = $rawHeadroomGB
        MinimumSourceFreeGB     = $MinimumSourceFreeGB
        MinimumTargetHeadroomGB = $MinimumTargetHeadroomGB
    }
}

function Get-SasBackupImageSourceContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDrive
    )

    $letter = ConvertTo-SasDriveLetter -DriveLetter $SourceDrive
    $root = '{0}:\' -f $letter
    $mountPoint = '{0}:' -f $letter

    $systemFiles = [ordered]@{}
    foreach ($name in @('hiberfil.sys', 'pagefile.sys', 'swapfile.sys')) {
        $item = Get-Item -LiteralPath (Join-Path $root $name) -Force -ErrorAction SilentlyContinue
        $systemFiles[$name] = $(if ($null -ne $item) { [math]::Round(([double]$item.Length / 1GB), 2) } else { $null })
    }

    $bitLocker = [ordered]@{
        Available        = $false
        ProtectionStatus = $null
        VolumeStatus     = $null
        EncryptionMethod = $null
    }

    if (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        try {
            $bl = Get-BitLockerVolume -MountPoint $mountPoint -ErrorAction Stop
            $bitLocker.Available = $true
            $bitLocker.ProtectionStatus = [string]$bl.ProtectionStatus
            $bitLocker.VolumeStatus = [string]$bl.VolumeStatus
            $bitLocker.EncryptionMethod = [string]$bl.EncryptionMethod
        }
        catch {
            $bitLocker.Available = $true
            $bitLocker.ProtectionStatus = 'QueryFailed'
        }
    }

    [pscustomobject]@{
        BitLocker         = [pscustomobject]$bitLocker
        SystemFileSizeGB  = [pscustomobject]$systemFiles
        WindowsOldPresent = (Test-Path -LiteralPath (Join-Path $root 'Windows.old'))
    }
}

function Test-SasBackupTargetStability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetDrive,

        [Parameter(Mandatory = $true)]
        [psobject]$Baseline,

        [ValidateRange(1, 120)]
        [int]$Samples = 5,

        [ValidateRange(0, 60)]
        [int]$DelaySeconds = 2
    )

    $passed = 0
    $failures = New-Object System.Collections.Generic.List[string]

    for ($i = 1; $i -le $Samples; $i++) {
        try {
            $current = Get-SasBackupImageVolumeRecord -DriveLetter $TargetDrive
            $sameIdentity = (
                $current.DiskNumber -eq $Baseline.DiskNumber -and
                $current.DiskFriendlyName -eq $Baseline.DiskFriendlyName -and
                $current.Label -eq $Baseline.Label -and
                $current.FileSystem -eq $Baseline.FileSystem
            )

            if ($sameIdentity) {
                $passed++
            }
            else {
                $failures.Add(('Sample {0}: target identity changed.' -f $i))
            }
        }
        catch {
            $failures.Add(('Sample {0}: target unavailable: {1}' -f $i, $_.Exception.Message))
        }

        if ($i -lt $Samples -and $DelaySeconds -gt 0) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    [pscustomobject]@{
        Passed        = ($passed -eq $Samples)
        Samples       = $Samples
        SamplesPassed = $passed
        Failures      = @($failures)
    }
}

function Invoke-SasBackupImagePreflight {
    [CmdletBinding()]
    param(
        [string]$SourceDrive = 'C',

        [Parameter(Mandatory = $true)]
        [string]$TargetDrive,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedTargetLabel,

        [ValidateRange(1, 1024)]
        [double]$MinimumSourceFreeGB = 20,

        [ValidateRange(0, 1024)]
        [double]$MinimumTargetHeadroomGB = 20,

        [ValidateRange(1, 120)]
        [int]$StabilitySamples = 5,

        [ValidateRange(0, 60)]
        [int]$StabilityDelaySeconds = 2
    )

    $source = Get-SasBackupImageVolumeRecord -DriveLetter $SourceDrive
    $target = Get-SasBackupImageVolumeRecord -DriveLetter $TargetDrive
    $stability = Test-SasBackupTargetStability -TargetDrive $TargetDrive -Baseline $target -Samples $StabilitySamples -DelaySeconds $StabilityDelaySeconds
    $decision = Test-SasBackupImagePreflightDecision -Source $source -Target $target -ExpectedTargetLabel $ExpectedTargetLabel -MinimumSourceFreeGB $MinimumSourceFreeGB -MinimumTargetHeadroomGB $MinimumTargetHeadroomGB -TargetStabilityPassed $stability.Passed
    $sourceContext = Get-SasBackupImageSourceContext -SourceDrive $SourceDrive

    [pscustomobject]@{
        SchemaVersion = 'sas-backup-image-preflight/v1'
        TimestampUtc  = [DateTime]::UtcNow.ToString('o')
        SafetyMode    = 'READ_ONLY_PREFLIGHT'
        Decision      = $decision.Decision
        Reasons       = $decision.Reasons
        Source        = $source
        Target        = $target
        Stability     = $stability
        Capacity      = [pscustomobject]@{
            RawHeadroomGB           = $decision.RawCapacityHeadroomGB
            MinimumTargetHeadroomGB = $decision.MinimumTargetHeadroomGB
        }
        Thresholds    = [pscustomobject]@{
            MinimumSourceFreeGB = $decision.MinimumSourceFreeGB
        }
        SourceContext = $sourceContext
    }
}

Export-ModuleMember -Function @(
    'Get-SasBackupImageVolumeRecord',
    'Test-SasBackupImagePreflightDecision',
    'Test-SasBackupTargetStability',
    'Invoke-SasBackupImagePreflight'
)
