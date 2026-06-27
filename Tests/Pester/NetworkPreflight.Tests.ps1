#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:preflight = Join-Path $script:repoRoot 'survey\sas-network-preflight.ps1'
}

Describe 'sas-network-preflight.ps1 lightweight Pester guard' {
    It 'exists' {
        $script:preflight | Should -Exist
    }

    It 'parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:preflight, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'keeps ambiguous identifiers separated from probe target columns' {
        $content = Get-Content -LiteralPath $script:preflight -Raw
        $content.Contains("`$targetColumns = @('Target')") | Should -BeTrue
        $content.Contains("`$identifierColumns = @('Identifier')") | Should -BeTrue
        $content.Contains('Skipping ambiguous Identifier value without explicit host/IP type') | Should -BeTrue
    }
}
