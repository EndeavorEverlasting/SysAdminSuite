#Requires -Modules Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:agentPath = Join-Path $script:repoRoot 'mapping\Agents\Invoke-NorthwellPrinterActiveUserAgent.ps1'
}

Describe 'Northwell active-user SID identity regression' {
    It 'uses the already-resolved SecurityIdentifier object when granting read access' {
        $text = Get-Content -LiteralPath $script:agentPath -Raw
        $text | Should -Match 'FileSystemAccessRule\(\s*\r?\n\s*\$sidObject,'
        $text | Should -Not -Match 'FileSystemAccessRule\(\s*\r?\n\s*\$sid,'
    }

    It 'uses the SID string for the interactive-token task identity after account translation succeeds' {
        $text = Get-Content -LiteralPath $script:agentPath -Raw
        $text | Should -Match '\$sidObject = \$account\.Translate\(\[System\.Security\.Principal\.SecurityIdentifier\]\)'
        $text | Should -Match '\$taskDefinition\.Principal\.UserId = \$sid'
        $text | Should -Match 'RegisterTaskDefinition\(\$userTaskName, \$taskDefinition, 6, \$sid, \$null, 3, \$null\)'
        $text | Should -Not -Match '\$taskDefinition\.Principal\.UserId = \$activeUser'
        $text | Should -Not -Match 'RegisterTaskDefinition\(\$userTaskName, \$taskDefinition, 6, \$activeUser,'
    }

    It 'keeps the original account name only for evidence and operator diagnostics' {
        $text = Get-Content -LiteralPath $script:agentPath -Raw
        $text | Should -Match 'ActiveUser = \$activeUser'
        $text | Should -Match 'ActiveUserSid = \$sid'
        $text | Should -Match 'Interactive-token printer task did not produce user proof within 45 seconds for \$activeUser'
    }
}
