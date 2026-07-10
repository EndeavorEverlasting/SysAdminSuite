#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:installer = Join-Path $script:repoRoot 'scripts\Invoke-SasSoftwareInstall.ps1'
}

Describe 'Invoke-SasSoftwareInstall safety behavior' {
    BeforeEach {
        $script:outputRoot = Join-Path $script:repoRoot ('survey\output\software_install\pester-' + [guid]::NewGuid().ToString('N'))
    }

    AfterEach {
        if ([System.IO.Directory]::Exists($script:outputRoot)) {
            [System.IO.Directory]::Delete($script:outputRoot, $true)
        }
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

    It 'accepts the approved root with case and separator normalization' {
        Mock New-PSSession { throw 'New-PSSession must not be called' }

        $summary = & $script:installer `
            -ComputerName 'synthetic-target' `
            -InstallerRelativePath 'Share/Package/setup.exe' `
            -SoftwareShareRoot '\\NT2KWB972SMS01/' `
            -OutputRoot $script:outputRoot `
            -WhatIf

        $summary.planned_count | Should -Be 1
        Should -Invoke New-PSSession -Times 0 -Exactly
    }

    It 'rejects a deceptive near-prefix software root' {
        Mock New-PSSession { throw 'New-PSSession must not be called' }

        {
            & $script:installer `
                -ComputerName 'synthetic-target' `
                -InstallerRelativePath 'Share\Package\setup.exe' `
                -SoftwareShareRoot '\\nt2kwb972sms01.evil\' `
                -OutputRoot $script:outputRoot `
                -WhatIf
        } | Should -Throw '*not an approved software source*'

        Should -Invoke New-PSSession -Times 0 -Exactly
    }

    It 'rejects rooted and parent-traversal installer paths before target contact' -ForEach @(
        @{ RejectedPath = 'C:\Temp\setup.exe'; ExpectedError = '*must be relative*' }
        @{ RejectedPath = 'Share\..\setup.exe'; ExpectedError = '*parent-directory traversal*' }
        @{ RejectedPath = 'Share/../setup.exe'; ExpectedError = '*parent-directory traversal*' }
    ) {
        Mock New-PSSession { throw 'New-PSSession must not be called' }

        {
            & $script:installer `
                -ComputerName 'synthetic-target' `
                -InstallerRelativePath $RejectedPath `
                -OutputRoot $script:outputRoot `
                -WhatIf
        } | Should -Throw $ExpectedError

        Should -Invoke New-PSSession -Times 0 -Exactly
    }

    It 'rejects output outside approved generated roots' {
        Mock New-PSSession { throw 'New-PSSession must not be called' }
        $outsideRoot = Join-Path $TestDrive 'outside-approved-output'

        {
            & $script:installer `
                -ComputerName 'synthetic-target' `
                -InstallerRelativePath 'Share\Package\setup.exe' `
                -OutputRoot $outsideRoot `
                -WhatIf
        } | Should -Throw '*outside approved generated output roots*'

        Should -Invoke New-PSSession -Times 0 -Exactly
    }

    It 'rejects a MaxTargets value above the 25-target ceiling' {
        {
            & $script:installer `
                -ComputerName 'synthetic-target' `
                -InstallerRelativePath 'Share\Package\setup.exe' `
                -MaxTargets 26 `
                -OutputRoot $script:outputRoot `
                -WhatIf
        } | Should -Throw '*MaxTargets*'
    }

    It 'keeps WhatIf local and does not probe the share or target' {
        Mock Test-Path { return $true }
        Mock New-PSSession { throw 'New-PSSession must not be called' }
        Mock Invoke-Command { throw 'Invoke-Command must not be called' }
        Mock Copy-Item { throw 'Copy-Item must not be called' }

        $summary = & $script:installer `
            -ComputerName 'synthetic-target' `
            -InstallerRelativePath 'Share\Package\setup.exe' `
            -OutputRoot $script:outputRoot `
            -WhatIf

        $summary.planned_count | Should -Be 1
        Should -Invoke Test-Path -Times 0 -Exactly -ParameterFilter { $LiteralPath -like '\\*' }
        Should -Invoke Test-Path -Times 0 -Exactly -ParameterFilter { $Path -like '\\*' }
        Should -Invoke Test-Path -Times 0 -Exactly -ParameterFilter { $args[0] -like '\\*' }
        Should -Invoke New-PSSession -Times 0 -Exactly
        Should -Invoke Invoke-Command -Times 0 -Exactly
        Should -Invoke Copy-Item -Times 0 -Exactly
    }

    It 'cleans run-specific staging after a copy failure' {
        Mock Test-Path { return $true }
        Mock New-PSSession {
            [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject(
                [System.Management.Automation.Runspaces.PSSession]
            )
        }
        Mock Invoke-Command {
            return "C:\ProgramData\SysAdminSuite\SoftwareInstall\$($ArgumentList[0])"
        } -ParameterFilter {
            $ScriptBlock.ToString() -match 'New-Item -ItemType Directory'
        } -RemoveParameterType Session
        Mock Invoke-Command {
            return [pscustomobject]@{
                cleanup_attempted = $true
                cleanup_succeeded = $true
                repo_artifact_remaining = $false
                pruned_empty_parent_dirs = @()
                error = $null
            }
        } -ParameterFilter {
            $ScriptBlock.ToString() -match 'repo_owned_stage_root'
        } -RemoveParameterType Session
        Mock Copy-Item { throw 'synthetic copy failure' } -RemoveParameterType ToSession
        Mock Remove-PSSession {} -RemoveParameterType Session

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
        Should -Invoke Invoke-Command -Times 1 -Exactly -ParameterFilter {
            $ScriptBlock.ToString() -match 'repo_owned_stage_root' -and
            $ArgumentList[0] -eq $summary.run_id
        }
        Should -Invoke Remove-PSSession -Times 1 -Exactly
    }

    It 'preserves the original failure and reports cleanup uncertainty' {
        Mock Test-Path { return $true }
        Mock New-PSSession {
            [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject(
                [System.Management.Automation.Runspaces.PSSession]
            )
        }
        Mock Invoke-Command {
            return "C:\ProgramData\SysAdminSuite\SoftwareInstall\$($ArgumentList[0])"
        } -ParameterFilter {
            $ScriptBlock.ToString() -match 'New-Item -ItemType Directory'
        } -RemoveParameterType Session
        Mock Invoke-Command {
            throw 'synthetic cleanup failure'
        } -ParameterFilter {
            $ScriptBlock.ToString() -match 'repo_owned_stage_root'
        } -RemoveParameterType Session
        Mock Copy-Item { throw 'synthetic copy failure' } -RemoveParameterType ToSession
        Mock Remove-PSSession {} -RemoveParameterType Session

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
        $summary.failed_count | Should -Be 1
        $summary.cleanup_failure_count | Should -Be 1
        $summary.repo_artifact_remaining_count | Should -Be 1
        Should -Invoke Invoke-Command -Times 1 -Exactly -ParameterFilter {
            $ScriptBlock.ToString() -match 'repo_owned_stage_root' -and
            $ArgumentList[0] -eq $summary.run_id
        }
        Should -Invoke Remove-PSSession -Times 1 -Exactly
    }

    It 'creates collision-safe run identifiers for back-to-back plans' {
        $first = & $script:installer `
            -ComputerName 'synthetic-target' `
            -InstallerRelativePath 'Share\Package\setup.exe' `
            -OutputRoot $script:outputRoot `
            -WhatIf
        $second = & $script:installer `
            -ComputerName 'synthetic-target' `
            -InstallerRelativePath 'Share\Package\setup.exe' `
            -OutputRoot $script:outputRoot `
            -WhatIf

        $first.run_id | Should -Not -Be $second.run_id
        $first.run_id | Should -Match '^software-install-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$'
        $second.run_id | Should -Match '^software-install-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$'
    }
}

