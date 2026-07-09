#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Tests for QRTasks dispatcher safety behaviors.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:dispatcherPath = Join-Path $repoRoot 'QRTasks\Invoke-TechTask.ps1'
    $script:powerComfortPath = Join-Path $repoRoot 'QRTasks\Set-PowerComfortDefaults.ps1'
    $script:displayMenuProbePath = Join-Path $repoRoot 'QRTasks\Test-DisplayMenuButtonEvent.ps1'
}

Describe 'Invoke-TechTask task registry' {
    It 'Includes WinOptionalFeatures mapped to Get-WindowsOptionalFeatures.ps1' {
        $content = Get-Content -Path $script:dispatcherPath -Raw
        $content | Should -Match "WinOptionalFeatures\s*=\s*'Get-WindowsOptionalFeatures\.ps1'"
    }

    It 'Includes PowerComfort mapped to Set-PowerComfortDefaults.ps1' {
        $content = Get-Content -Path $script:dispatcherPath -Raw
        $content | Should -Match "PowerComfort\s*=\s*'Set-PowerComfortDefaults\.ps1'"
    }

    It 'Includes PowerComfortRevert mapped to Restore-PowerComfortDefaults.ps1' {
        $content = Get-Content -Path $script:dispatcherPath -Raw
        $content | Should -Match "PowerComfortRevert\s*=\s*'Restore-PowerComfortDefaults\.ps1'"
    }

    It 'Includes DisplayMenuButtonProbe mapped to Test-DisplayMenuButtonEvent.ps1' {
        $content = Get-Content -Path $script:dispatcherPath -Raw
        $content | Should -Match "DisplayMenuButtonProbe\s*=\s*'Test-DisplayMenuButtonEvent\.ps1'"
    }
}

Describe 'Set-PowerComfortDefaults button behavior' {
    It 'Sets the physical power button and Windows Start menu power button to do nothing on AC and DC' {
        $content = Get-Content -Path $script:powerComfortPath -Raw
        $content | Should -Match '\$powerButtonAction\s*=\s*''7648efa3-dd9c-4e3e-b566-50f929386280'''
        $content | Should -Match '\$startMenuPowerButtonAction\s*=\s*''a7066653-8d6c-40a8-910e-a1f54b84c7e5'''
        $content.Contains("@('/setacvalueindex', `$g, 'SUB_BUTTONS', `$powerButtonAction, '0')") | Should -Be $true
        $content.Contains("@('/setdcvalueindex', `$g, 'SUB_BUTTONS', `$powerButtonAction, '0')") | Should -Be $true
        $content.Contains("@('/setacvalueindex', `$g, 'SUB_BUTTONS', `$startMenuPowerButtonAction, '0')") | Should -Be $true
        $content.Contains("@('/setdcvalueindex', `$g, 'SUB_BUTTONS', `$startMenuPowerButtonAction, '0')") | Should -Be $true
    }

    It 'Names the Start menu power button behavior in the operator report text' {
        $content = Get-Content -Path $script:powerComfortPath -Raw
        $content | Should -Match 'start menu power button=do nothing'
    }
}

Describe 'Test-DisplayMenuButtonEvent field probe' {
    It 'Classifies the physical display/menu button separately from Windows power policy' {
        $content = Get-Content -Path $script:displayMenuProbePath -Raw
        $content | Should -Match 'physical display/menu button'
        $content | Should -Match 'OBSERVED_WINDOWS_EVENT'
        $content | Should -Match 'NO_WINDOWS_EVENT_OBSERVED'
        $content | Should -Match 'firmware-only / OSD-controlled'
        $content | Should -Match 'DisplayMenuButtonProbe'
    }

    It 'Remains read-only except for local QRTasks report output' {
        $content = Get-Content -Path $script:displayMenuProbePath -Raw
        $forbidden = @(
            'powercfg /set',
            'Set-ItemProperty',
            'New-ItemProperty',
            'Remove-ItemProperty',
            'Register-ScheduledTask',
            'New-Service',
            'wevtutil cl',
            'Clear-EventLog'
        )
        foreach ($fragment in $forbidden) {
            $content | Should -Not -Match ([regex]::Escape($fragment))
        }
        $content | Should -Match 'Get-WinEvent'
        $content | Should -Match 'GetInfo\\Output\\QRTasks'
    }
}

Describe 'Invoke-TechTask fallback root resolution' {
    It 'Exposes localhost and computername fallback candidates in resolver implementation' {
        $content = Get-Content -Path $script:dispatcherPath -Raw
        # Substring checks avoid .NET regex quirks with `\c` and backslashes
        $content.Contains('localhost\c$\Scripts\QRTasks') | Should -Be $true
        $content.Contains('COMPUTERNAME\c$\Scripts\QRTasks') | Should -Be $true
    }

    It 'Uses local dispatcher fallback when requested root is missing' {
        $qrTasksRoot = Join-Path $repoRoot 'QRTasks'
        . $script:dispatcherPath -Task '?'
        Mock Test-Path {
            param([string]$LiteralPath)
            $LiteralPath -eq $qrTasksRoot
        }

        $resolved = Resolve-TaskScriptRoot -RequestedRoot 'C:\Missing\QRTasks'
        $resolved.Path | Should -Be $qrTasksRoot
        $resolved.Reason | Should -Be 'local dispatcher folder fallback'
        $resolved.Resolution | Should -Match 'unreachable: C:\\Missing\\QRTasks'
    }
}

Describe 'Invoke-TechTask existing protections' {
    It 'Returns warning for unknown task without throwing' {
        $warnings = & $script:dispatcherPath -Task 'Nope' 3>&1
        ($warnings | Out-String) | Should -Match "Unknown task"
    }

    It 'Returns warning when mapped script is missing under selected root' {
        $root = Join-Path $TestDrive 'qr-missing'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        $warnings = & $script:dispatcherPath -Task 'ModelInfo' -ScriptRoot $root 3>&1
        ($warnings | Out-String) | Should -Match 'Task script not found'
    }

    It 'Enforces timeout and force-stops long-running mapped tasks' {
        $root = Join-Path $TestDrive 'qr-timeout'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'Get-RAMProfile.ps1') -Value 'Start-Sleep -Seconds 6' -Encoding UTF8

        {
            & $script:dispatcherPath -Task 'RAMProfile' -ScriptRoot $root -TaskTimeoutSec 5
        } | Should -Throw -ExpectedMessage "*exceeded timeout*"
    }
}
