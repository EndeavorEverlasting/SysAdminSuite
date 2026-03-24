#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }
<#
.SYNOPSIS
    Offline unit tests for Utilities\ scripts.
    All tests run without network access, AD, or real printers.
    Safe to run on any machine — no side effects.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'Utilities\Test-Network.ps1')
    . (Join-Path $repoRoot 'Utilities\Map-Printer.ps1')
    . (Join-Path $repoRoot 'Utilities\Invoke-FileShare.ps1')
}

Describe 'Test-Network' {
    Context 'Parameter contract' {
        It 'Has a ComputerName parameter (not $Host)' {
            $cmd = Get-Command Test-Network
            $cmd.Parameters.Keys | Should -Contain 'ComputerName'
            $cmd.Parameters.Keys | Should -Not -Contain 'Host'
        }

        It 'Accepts multiple targets via array' {
            $cmd = Get-Command Test-Network
            $cmd.Parameters['ComputerName'].ParameterType | Should -Be ([string[]])
        }

        It 'Returns one result object per target' {
            # Mock Test-Connection so no real network call is made
            Mock Test-Connection { $true }

            $results = Test-Network -ComputerName 'fake-host-1','fake-host-2'
            $results.Count | Should -Be 2
            $results[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
            $results[0].PSObject.Properties.Name | Should -Contain 'Reachable'
        }
    }

    Context 'Offline safety' {
        It 'Does not throw when host is unreachable' {
            Mock Test-Connection { $false }
            { Test-Network -ComputerName '192.0.2.1' } | Should -Not -Throw
        }

        It 'Returns Reachable=$false for unreachable host' {
            Mock Test-Connection { $false }
            $r = Test-Network -ComputerName '192.0.2.1'
            $r.Reachable | Should -Be $false
        }
    }
}

Describe 'Map-Printer' {
    Context 'WhatIf / dry-run support' {
        It 'Supports ShouldProcess (-WhatIf)' {
            $cmd = Get-Command Map-Printer
            $cmd.Parameters.Keys | Should -Contain 'WhatIf'
        }

        It 'Does NOT call Add-Printer when -WhatIf is set' {
            Mock Add-Printer { throw 'Should not be called' }
            { Map-Printer -PrinterPath '\\FAKE\Queue' -WhatIf } | Should -Not -Throw
            Should -Invoke Add-Printer -Times 0
        }
    }

    Context 'Parameter validation' {
        It 'Requires PrinterPath' {
            $cmd = Get-Command Map-Printer
            $cmd.Parameters['PrinterPath'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }
    }
}

Describe 'Invoke-FileShare' {
    Context 'Error handling' {
        It 'Throws a descriptive error when share is unreachable' {
            Mock Test-Path { $false }
            { Invoke-FileShare -SharePath '\\FAKE\C$' } | Should -Throw -ExpectedMessage '*Cannot access share*'
        }

        It 'Calls Get-ChildItem when share is reachable' {
            Mock Test-Path { $true }
            Mock Get-ChildItem { @([pscustomobject]@{ Name='file.txt' }) }
            $result = Invoke-FileShare -SharePath '\\FAKE\C$'
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke Get-ChildItem -Times 1
        }
    }
}

