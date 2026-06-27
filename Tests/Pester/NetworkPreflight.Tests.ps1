#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:preflight = Join-Path $script:repoRoot 'survey\sas-network-preflight.ps1'
}

Describe 'sas-network-preflight.ps1 identity and folder contracts' {
    It 'parses without PowerShell syntax errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:preflight, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'uses codified target intake roots and generated output roots' {
        $content = Get-Content -LiteralPath $script:preflight -Raw
        $content | Should -Match 'targetsLocalRoot'
        $content | Should -Match 'logsTargetsRoot'
        $content | Should -Match 'surveyInputRoot'
        $content | Should -Match 'surveyOutputRoot'
        $content | Should -Match 'logsNmapRoot'
        $content | Should -Match 'surveyArtifactsRoot'
    }

    It 'prints progress with stage and per-check percentages' {
        $content = Get-Content -LiteralPath $script:preflight -Raw
        $content | Should -Match 'Write-SasStageProgress'
        $content | Should -Match 'PercentComplete'
        $content | Should -Match '\[\$Step/\$Total\]'
        $content | Should -Match '\[\$checkNumber/\$totalChecks\]'
    }

    It 'does not treat ambiguous Identifier values as probe targets by default' {
        $content = Get-Content -LiteralPath $script:preflight -Raw
        $content | Should -Match 'function Get-ExplicitTargetType'
        $content | Should -Match 'function Test-ExplicitNonHostType'
        $content | Should -Match "\$targetColumns = @\('Target'\)"
        $content | Should -Match "\$identifierColumns = @\('Identifier'\)"
        $content | Should -Match 'Skipping ambiguous Identifier value without explicit host/IP type'
        $content | Should -Match 'Serial-only rows must be normalized or enriched'
    }

    It 'accepts explicit host and address columns without requiring ambiguous Identifier fallback' {
        $content = Get-Content -LiteralPath $script:preflight -Raw
        foreach ($column in @('HostName', 'Hostname', 'ComputerName', 'DeviceName', 'Name', 'DnsName', 'DNSName', 'FQDN', 'IPAddress', 'IP', 'IPv4')) {
            $content | Should -Match $column
        }
    }
}
