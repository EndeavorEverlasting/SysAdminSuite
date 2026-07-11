$modulePath = Join-Path $PSScriptRoot '..\..\scripts\SasProgress.psm1'

Describe 'SysAdminSuite PowerShell progress contract' {
    BeforeAll {
        Import-Module $modulePath -Force
    }

    It 'supports every required lifecycle state' {
        $text = Get-Content -LiteralPath $modulePath -Raw
        foreach ($state in @('running', 'waiting', 'complete', 'failed', 'skipped')) {
            $text | Should -Match ([regex]::Escape("'$state'"))
        }
    }

    It 'suppresses human progress without writing success output' {
        $context = New-SasProgressContext -Activity 'contract' -Total 2 -NoProgress
        $output = @(Write-SasProgressState -Context $context -State running -Status 'first' -Current 1)
        $output.Count | Should -Be 0
        $context.Current | Should -Be 1
        $context.Terminal | Should -BeFalse
    }

    It 'marks <State> terminal' -TestCases @(
        @{ State = 'complete' }
        @{ State = 'failed' }
        @{ State = 'skipped' }
    ) {
        param($State)
        $context = New-SasProgressContext -Activity 'contract' -Total 1 -NoProgress
        Write-SasProgressState -Context $context -State $State -Status 'terminal'
        $context.Terminal | Should -BeTrue
    }

    It 'keeps waiting nonterminal' {
        $context = New-SasProgressContext -Activity 'contract' -Total 2 -NoProgress
        Write-SasProgressState -Context $context -State waiting -Status 'operator input' -Current 1
        $context.Terminal | Should -BeFalse
        $context.Current | Should -Be 1
    }
}
