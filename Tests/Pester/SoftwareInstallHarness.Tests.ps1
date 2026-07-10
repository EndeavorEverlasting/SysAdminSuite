#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:installer = Join-Path $script:repoRoot 'scripts\Invoke-SasSoftwareInstall.ps1'
}

Describe 'Invoke-SasSoftwareInstall safety behavior' {
    BeforeEach {
        $script:outputRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'exists and parses' {
        $script:installer | Should -Exist
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:installer, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'rejects an arbitrary UNC root before contacting it' {
        Mock New-PSSession { throw 'New-PSSession must not be called' }

        {
            & $script:installer `
                -ComputerName 'synthetic-target' `
                -InstallerRelativePath 'Share\Package\setup.exe' `
                -SoftwareShareRoot '\\unapproved-server\' `
                -OutputRoot $script:outputRoot `
                -WhatIf
        } | Should -Throw '*not an approved software source*'

        Should -Invoke New-PSSession -Times 0 -Exactly
    }

    It 'keeps WhatIf local and does not probe the share or target' {
        $script:testedPaths = [System.Collections.Generic.List[string]]::new()
        Mock Test-Path {
            param($LiteralPath)
            $script:testedPaths.Add([string]$LiteralPath)
            return $true
        }
        Mock New-PSSession { throw 'New-PSSession must not be called' }
        Mock Invoke-Command { throw 'Invoke-Command must not be called' }
        Mock Copy-Item { throw 'Copy-Item must not be called' }

        $summary = & $script:installer `
            -ComputerName 'synthetic-target' `
            -InstallerRelativePath 'Share\Package\setup.exe' `
            -OutputRoot $script:outputRoot `
            -WhatIf

        $summary.planned_count | Should -Be 1
        @($script:testedPaths | Where-Object { $_.StartsWith('\\') }).Count | Should -Be 0
        Should -Invoke New-PSSession -Times 0 -Exactly
        Should -Invoke Invoke-Command -Times 0 -Exactly
        Should -Invoke Copy-Item -Times 0 -Exactly
    }

    It 'cleans run-specific staging after a copy failure' {
        $script:remoteCall = 0
        Mock Test-Path { return $true }
        Mock New-PSSession { [pscustomobject]@{ ComputerName = 'synthetic-target' } }
        Mock Invoke-Command {
            $script:remoteCall++
            if ($script:remoteCall -eq 1) {
                return 'C:\ProgramData\SysAdminSuite\SoftwareInstall\software-install-20260710-120000'
            }
            return [pscustomobject]@{
                cleanup_attempted = $true
                cleanup_succeeded = $true
                repo_artifact_remaining = $false
                pruned_empty_parent_dirs = @()
                error = $null
            }
        }
        Mock Copy-Item { throw 'synthetic copy failure' }
        Mock Remove-PSSession {}

        $summary = & $script:installer `
            -ComputerName 'synthetic-target' `
            -InstallerRelativePath 'Share\Package\setup.exe' `
            -InstallMode CopyThenInstall `
            -OutputRoot $script:outputRoot `
            -AllowTargetMutation `
            -Confirm:$false

        $summary.failed_count | Should -Be 1
        $summary.results[0].error | Should -Match 'synthetic copy failure'
        $summary.results[0].cleanup_attempted | Should -BeTrue
        $summary.results[0].cleanup_succeeded | Should -BeTrue
        $summary.results[0].repo_artifact_remaining | Should -BeFalse
        Should -Invoke Invoke-Command -Times 2 -Exactly
        Should -Invoke Remove-PSSession -Times 1 -Exactly
    }

    It 'preserves the original failure and reports cleanup uncertainty' {
        $script:remoteCall = 0
        Mock Test-Path { return $true }
        Mock New-PSSession { [pscustomobject]@{ ComputerName = 'synthetic-target' } }
        Mock Invoke-Command {
            $script:remoteCall++
            if ($script:remoteCall -eq 1) {
                return 'C:\ProgramData\SysAdminSuite\SoftwareInstall\software-install-20260710-120000'
            }
            throw 'synthetic cleanup failure'
        }
        Mock Copy-Item { throw 'synthetic copy failure' }
        Mock Remove-PSSession {}

        $summary = & $script:installer `
            -ComputerName 'synthetic-target' `
            -InstallerRelativePath 'Share\Package\setup.exe' `
            -InstallMode CopyThenInstall `
            -OutputRoot $script:outputRoot `
            -AllowTargetMutation `
            -Confirm:$false

        $summary.results[0].error | Should -Match 'synthetic copy failure; cleanup failed: synthetic cleanup failure'
        $summary.results[0].cleanup_attempted | Should -BeTrue
        $summary.results[0].cleanup_succeeded | Should -BeFalse
        $summary.results[0].repo_artifact_remaining | Should -BeTrue
        $summary.cleanup_failure_count | Should -Be 1
        $summary.repo_artifact_remaining_count | Should -Be 1
        Should -Invoke Remove-PSSession -Times 1 -Exactly
    }
}
