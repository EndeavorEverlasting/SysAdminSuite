#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:modulePath = Join-Path $script:repoRoot 'mapping\Modules\NorthwellPrinterMapping.Core.psm1'
    Import-Module $script:modulePath -Force
}

Describe 'Northwell printer singleton Status.json proof contract' {
    It 'classifies one missing queue without a strict-mode Count property failure' {
        $status = [pscustomobject]@{
            Success = $false
            Identity = 'NT AUTHORITY\SYSTEM'
            Missing = '\\printsrv01\queue01'
        }

        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINTSRV01\QUEUE01') } |
            Should -Throw '*Missing machine-wide queue(s):*queue01*'
    }

    It 'accepts a singleton machine-wide queue value when the requested queue is proven' {
        $status = [pscustomobject]@{
            Success = $true
            Identity = 'NT AUTHORITY\SYSTEM'
            MachineWideUNC = '\\printsrv01\queue01'
            Missing = @()
        }

        { Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters @('\\PRINTSRV01\QUEUE01') } |
            Should -Not -Throw
    }
}
