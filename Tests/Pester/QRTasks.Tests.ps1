#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Tests for QRTasks dispatcher safety behaviors.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:dispatcherPath = Join-Path $repoRoot 'QRTasks\Invoke-TechTask.ps1'
}

Describe 'Invoke-TechTask fallback root resolution' {
    It 'Exposes localhost and computername fallback candidates in resolver implementation' {
        $content = Get-Content -Path $script:dispatcherPath -Raw
        $content | Should -Match '\\\\localhost\\c\$\Scripts\\QRTasks'
        $content | Should -Match '\\\\\$env:COMPUTERNAME\\c\$\Scripts\\QRTasks'
    }

    It 'Uses local dispatcher fallback when requested root is missing' {
        . $script:dispatcherPath -Task '?'
        Mock Test-Path {
            param([string]$LiteralPath)
            $LiteralPath -eq $PSScriptRoot
        }

        $resolved = Resolve-TaskScriptRoot -RequestedRoot 'C:\Missing\QRTasks'
        $resolved.Path | Should -Be $PSScriptRoot
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
