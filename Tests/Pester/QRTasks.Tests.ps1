#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Tests for QRTasks dispatcher safety behaviors.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:dispatcherPath = Join-Path $repoRoot 'QRTasks\Invoke-TechTask.ps1'
}

Describe 'Invoke-TechTask task registry' {
    It 'Includes WinOptionalFeatures mapped to Get-WindowsOptionalFeatures.ps1' {
        $content = Get-Content -Path $script:dispatcherPath -Raw
        $content | Should -Match "WinOptionalFeatures\s*=\s*'Get-WindowsOptionalFeatures\.ps1'"
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
