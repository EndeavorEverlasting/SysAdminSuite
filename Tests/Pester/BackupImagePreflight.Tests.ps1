#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $modulePath = Join-Path $repoRoot 'scripts\SasBackupImagePreflight.psm1'
    $runnerPath = Join-Path $repoRoot 'scripts\Test-SasBackupImagePreflight.ps1'
    Import-Module $modulePath -Force

    function New-TestVolumeRecord {
        param(
            [string]$DriveLetter,
            [int]$DiskNumber,
            [string]$Label,
            [string]$FileSystem = 'NTFS',
            [double]$UsedGB = 200,
            [double]$FreeGB = 100,
            [string]$VolumeHealthStatus = 'Healthy',
            [string]$DiskHealthStatus = 'Healthy',
            [string]$VolumeOperationalStatus = 'OK',
            [string]$DiskOperationalStatus = 'Online'
        )

        [pscustomobject]@{
            DriveLetter             = $DriveLetter
            DiskNumber              = $DiskNumber
            Label                   = $Label
            FileSystem              = $FileSystem
            UsedGB                  = $UsedGB
            FreeGB                  = $FreeGB
            VolumeHealthStatus      = $VolumeHealthStatus
            DiskHealthStatus        = $DiskHealthStatus
            VolumeOperationalStatus = $VolumeOperationalStatus
            DiskOperationalStatus   = $DiskOperationalStatus
        }
    }
}

Describe 'Backup image preflight contracts' {
    It 'parses the module and runner without PowerShell syntax errors' {
        foreach ($path in @($modulePath, $runnerPath)) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }
    }

    It 'contains no disk or volume mutation commands' {
        $content = (Get-Content -LiteralPath $modulePath -Raw) + "`n" + (Get-Content -LiteralPath $runnerPath -Raw)
        $forbidden = @(
            'Format-Volume', 'Repair-Volume', 'Clear-Disk', 'Initialize-Disk',
            'New-Partition', 'Remove-Partition', 'Resize-Partition', 'Set-Partition',
            'Set-Disk', 'Dismount-DiskImage', 'Mount-DiskImage', 'chkdsk',
            'manage-bde\s+-(off|on|pause|resume)', 'powercfg\s+/h\s+(off|on)'
        )
        foreach ($pattern in $forbidden) {
            $content | Should -Not -Match $pattern
        }
    }

    It 'returns READY only for a separate, healthy, stable NTFS target with sufficient headroom' {
        $source = New-TestVolumeRecord -DriveLetter 'C' -DiskNumber 0 -Label 'OS' -UsedGB 600 -FreeGB 40
        $target = New-TestVolumeRecord -DriveLetter 'D' -DiskNumber 1 -Label 'BackupTarget' -UsedGB 0 -FreeGB 900

        $result = Test-SasBackupImagePreflightDecision -Source $source -Target $target -ExpectedTargetLabel 'BackupTarget' -MinimumSourceFreeGB 20 -MinimumTargetHeadroomGB 20 -TargetStabilityPassed $true

        $result.Decision | Should -Be 'READY'
        $result.Reasons | Should -BeNullOrEmpty
        $result.RawCapacityHeadroomGB | Should -Be 300
    }

    It 'blocks a target-label mismatch before backup use' {
        $source = New-TestVolumeRecord -DriveLetter 'C' -DiskNumber 0 -Label 'OS' -UsedGB 600 -FreeGB 40
        $target = New-TestVolumeRecord -DriveLetter 'D' -DiskNumber 1 -Label 'WrongTarget' -UsedGB 0 -FreeGB 900

        $result = Test-SasBackupImagePreflightDecision -Source $source -Target $target -ExpectedTargetLabel 'BackupTarget'

        $result.Decision | Should -Be 'BLOCKED'
        $result.Reasons | Should -Contain 'TARGET_LABEL_MISMATCH'
    }

    It 'blocks when source and target resolve to the same physical disk' {
        $source = New-TestVolumeRecord -DriveLetter 'C' -DiskNumber 0 -Label 'OS' -UsedGB 600 -FreeGB 40
        $target = New-TestVolumeRecord -DriveLetter 'D' -DiskNumber 0 -Label 'BackupTarget' -UsedGB 0 -FreeGB 900

        $result = Test-SasBackupImagePreflightDecision -Source $source -Target $target -ExpectedTargetLabel 'BackupTarget'

        $result.Decision | Should -Be 'BLOCKED'
        $result.Reasons | Should -Contain 'SOURCE_TARGET_SAME_PHYSICAL_DISK'
    }

    It 'blocks a non-NTFS target' {
        $source = New-TestVolumeRecord -DriveLetter 'C' -DiskNumber 0 -Label 'OS' -UsedGB 600 -FreeGB 40
        $target = New-TestVolumeRecord -DriveLetter 'D' -DiskNumber 1 -Label 'BackupTarget' -FileSystem 'exFAT' -UsedGB 0 -FreeGB 900

        $result = Test-SasBackupImagePreflightDecision -Source $source -Target $target -ExpectedTargetLabel 'BackupTarget'

        $result.Decision | Should -Be 'BLOCKED'
        $result.Reasons | Should -Contain 'TARGET_FILESYSTEM_NOT_NTFS'
    }

    It 'blocks low source free space rather than beginning cleanup or imaging' {
        $source = New-TestVolumeRecord -DriveLetter 'C' -DiskNumber 0 -Label 'OS' -UsedGB 900 -FreeGB 5
        $target = New-TestVolumeRecord -DriveLetter 'D' -DiskNumber 1 -Label 'BackupTarget' -UsedGB 0 -FreeGB 950

        $result = Test-SasBackupImagePreflightDecision -Source $source -Target $target -ExpectedTargetLabel 'BackupTarget' -MinimumSourceFreeGB 20

        $result.Decision | Should -Be 'BLOCKED'
        $result.Reasons | Should -Contain 'SOURCE_FREE_SPACE_BELOW_MINIMUM'
    }

    It 'blocks insufficient raw target-capacity headroom' {
        $source = New-TestVolumeRecord -DriveLetter 'C' -DiskNumber 0 -Label 'OS' -UsedGB 900 -FreeGB 40
        $target = New-TestVolumeRecord -DriveLetter 'D' -DiskNumber 1 -Label 'BackupTarget' -UsedGB 0 -FreeGB 910

        $result = Test-SasBackupImagePreflightDecision -Source $source -Target $target -ExpectedTargetLabel 'BackupTarget' -MinimumTargetHeadroomGB 20

        $result.Decision | Should -Be 'BLOCKED'
        $result.Reasons | Should -Contain 'TARGET_RAW_CAPACITY_HEADROOM_BELOW_MINIMUM'
    }

    It 'blocks an unstable target connection' {
        $source = New-TestVolumeRecord -DriveLetter 'C' -DiskNumber 0 -Label 'OS' -UsedGB 600 -FreeGB 40
        $target = New-TestVolumeRecord -DriveLetter 'D' -DiskNumber 1 -Label 'BackupTarget' -UsedGB 0 -FreeGB 900

        $result = Test-SasBackupImagePreflightDecision -Source $source -Target $target -ExpectedTargetLabel 'BackupTarget' -TargetStabilityPassed $false

        $result.Decision | Should -Be 'BLOCKED'
        $result.Reasons | Should -Contain 'TARGET_CONNECTION_NOT_STABLE'
    }
}
